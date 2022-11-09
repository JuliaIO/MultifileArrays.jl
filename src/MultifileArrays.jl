"""
MultifileArrays creates lazily-loaded multidimensional arrays from files. Here are the main functions:

- `load_chunked`: Load an array from chunks stored in files in `filenames`.
- `load_series`: Create a lazily-loaded array `A` from a set of files.
- `select_series`: Create a vector of filenames from `filepattern`.
"""
module MultifileArrays

using SparseArrays   # only for ambiguity resolution
using Requires

export select_series, load_series, load_chunked

struct MultifileArray{T,N,A<:AbstractArray,NF,F} <: AbstractArray{T,N}
    filenames::Array{String,NF}
    buffer::A
    idx::Base.RefValue{CartesianIndex{NF}}
    loader::F

    function MultifileArray{T,N,A,NF,F}(filenames, buffer, loader) where {T,N,A<:AbstractArray,NF,F}
        idx = Ref(CartesianIndex(ntuple(i->0, NF)))
        return new{T,N,A,NF,F}(filenames, buffer, idx, loader)
    end
end

MultifileArray(filenames, buffer, loader) =
    MultifileArray{eltype(buffer),ndims(buffer)+ndims(filenames),typeof(buffer),ndims(filenames),typeof(loader)}(filenames, buffer, loader)

Base.size(A::MultifileArray) = (size(A.buffer)..., size(A.filenames)...)
Base.axes(A::MultifileArray) = (axes(A.buffer)..., axes(A.filenames)...)

split_index(::Type{<:MultifileArray{T,N,A}}, I) where {T,N,A<:AbstractArray} =
    Base.IteratorsMD.split(I, Val(ndims(A)))
split_index(MFA::AbstractArray, I) = split_index(typeof(MFA), I)

Base.@propagate_inbounds function setbuffer!(MFA::MultifileArray, Ifn)
    Base.@boundscheck checkbounds(MFA.filenames, Ifn)
    if Ifn != MFA.idx[]
        @inbounds MFA.loader(MFA.buffer, MFA.filenames[Ifn])
        MFA.idx[] = Ifn
    end
    return nothing
end

Base.@propagate_inbounds function Base.getindex(MFA::MultifileArray{T,N,A}, I::Vararg{Int,N}) where {T,N,A<:AbstractArray}
    Ibuf, Ifn = split_index(MFA, CartesianIndex(I))
    Base.@boundscheck checkbounds(MFA.buffer, Ibuf)
    @inbounds setbuffer!(MFA, Ifn)
    @inbounds return MFA.buffer[Ibuf]
end

@inline _axes(::Integer, args...) = (Base.OneTo(1), _axes(args...)...)
@inline _axes(ax::AbstractRange, args...) = (axes(ax)[1], _axes(args...)...)
_axes() = ()

@inline notinteger(::Integer, args...) = notinteger(args...)
@inline notinteger(::Any, args...) = (true, notinteger(args...)...)
notinteger() = ()

# Performance optimization: copy buffer-chunks to a target array
function _copyto!(dest::AbstractArray, src::SubArray{T,N,<:MultifileArray}) where {T,N}
    srcP = parent(src)
    indsbuf, indsfn = split_index(srcP, src.indices)
    destpre, destpost = Base.IteratorsMD.split(axes(dest), Val(length(notinteger(indsbuf...))))
    colons = map(x -> :, destpre)
    for (destslice, srcslice) in zip(CartesianIndices(destpost), CartesianIndices(_axes(indsfn...)))
        idxfn = CartesianIndex(map(getindex, indsfn, Tuple(srcslice)))
        setbuffer!(srcP, idxfn)
        copy!(view(dest, colons..., destslice), view(srcP.buffer, indsbuf...))
    end
    return dest
end
Base.copyto!(dest::AbstractArray, src::SubArray{T,N,<:MultifileArray}) where {T,N} =
    _copyto!(dest, src)
# Ambiguity resolution
Base.copyto!(dest::PermutedDimsArray, src::SubArray{T,N,<:MultifileArray}) where {T,N} =
    _copyto!(dest, src)
Base.copyto!(dest::PermutedDimsArray{T,N}, src::SubArray{T,N,<:MultifileArray}) where {T,N} =
    _copyto!(dest, src)
if isdefined(SparseArrays, :AbstractCompressedVector)
    Base.copyto!(dest::SparseArrays.AbstractCompressedVector, src::SubArray{T,1,<:MultifileArray}) where {T} =
        invoke(copyto!, (SparseArrays.AbstractCompressedVector, AbstractVector), dest, src)
else
    Base.copyto!(dest::SparseVector, src::SubArray{T,1,<:MultifileArray}) where {T,N} =
        _copyto!(dest, src)
end

## User-level API

function select_series(filepattern::Regex; dir=pwd())
    filenames = String[]
    order = Int[]
    for filename in readdir(dir)
        m = match(filepattern, filename)
        m === nothing && continue
        push!(filenames, joinpath(dir, filename))
        push!(order, (parse.(Int, m.captures)...,)...)
    end
    isempty(filenames) && throw(ArgumentError("no files in $dir matched $filepattern"))
    p = sortperm(order)
    return filenames[p]
end

"""
    filenames = select_series(filepattern; dir=pwd())

Create a vector of filenames from `filepattern`. `filepattern` may be a string containing a `*` character
or a regular expression capturing a digit-substring. The `*`/`capture` extracts an integer that determines file order.

When `dir` contains no extraneous files, and the filenames are ordered alphabetically in the desired sequence,
then `readdir` is a simpler alternative. `select_series` may be useful for cases that don't satisfy both of these conditions.

# Examples

Suppose you have a directory with `myimage_1.png`, `myimage_2.png`, ..., `myimage_12.png`. Then

```julia
julia> select_series("myimage_*.png")
12-element Vector{String}:
 "myimage_1.png"
 "myimage_2.png"
 ⋮
 "myimage_12.png"
```

!!! note
    The `myimage_` part of the string is essential: the `*` must match only integer data.
"""
function select_series(filepattern::AbstractString; kwargs...)
    if isabspath(filepattern) && isempty(kwargs)
        path, filepattern = dirname(filepattern), basename(filepattern)
        kwargs = (dir=path,)
    end
    rex = Regex(join(split(filepattern, '*'), "(\\d+)"))
    return select_series(rex; kwargs...)
end

"""
    A = load_series(f, filepattern; dir=pwd())

Create a lazily-loaded array `A` from a set of files. `f(filename)` should create an array from the `filename`,
and `filepattern` is a pattern matching the names of the desired files. The file names should have a numeric
portion that indicates ordering; ordering is numeric rather than alphabetical, so left-padding with zeros is optional.
See [`select_series`](@ref) for details about the pattern-matching.

# Examples

Suppose you are currently in a directory with files `image01.tiff` ... `image12.tiff`. Then either

```julia
julia> using FileIO, MultifileArrays

julia> img = load_series(load, "image*.tiff")
```

or the more precise regular-expression form

```julia
julia> img = load_series(load, r"image(\\d+).tiff");
```

suffice to load the image files.
"""
function load_series(f, filepattern; kwargs...)
    filenames = select_series(filepattern; kwargs...)
    buffer = f(first(filenames))
    return load_series((b, fn) -> copyto!(b, f(fn)), filenames, buffer)
end

"""
    A = load_series(f, filenames::AbstractArray{<:AbstractString}, buffer::AbstractArray)

Create a lazily-loaded array `A` from a set of files. `f` is a function to load the data from a specific file
into an array equivalent to `buffer`, meaning that

```julia
f(buffer, filename)
```

should fill `buffer` with the contents of `filename`.

`filenames` should be an array of file names with shape equivalent to the trailing dimensions of `A`, i.e., those
that follow the dimensions of `buffer`.

The advantage of this syntax is that it provides greater control than [`load_series(f, filepattern)`](@ref) over the
choice of files and the shape of the overall output.

# Examples

Suppose you are currently in a directory with files `image_z=1_t=1.tiff` through `image_z=5_t=30.tiff`,
where each file corresponds to a 2d `(x, y)` slice and the filename indicates the `z` and `t` coordinates.
You could reshape `filenames` into matrix form

```julia
5×30 Matrix{String}:
 "image_z=1_t=1.tiff"  "image_z=1_t=2.tiff"  "image_z=1_t=3.tiff"  …  "image_z=1_t=29.tiff"  "image_z=1_t=30.tiff"
 "image_z=2_t=1.tiff"  "image_z=2_t=2.tiff"  "image_z=2_t=3.tiff"     "image_z=2_t=29.tiff"  "image_z=2_t=30.tiff"
 "image_z=3_t=1.tiff"  "image_z=3_t=2.tiff"  "image_z=3_t=3.tiff"     "image_z=3_t=29.tiff"  "image_z=3_t=30.tiff"
 "image_z=4_t=1.tiff"  "image_z=4_t=2.tiff"  "image_z=4_t=3.tiff"     "image_z=4_t=29.tiff"  "image_z=4_t=30.tiff"
 "image_z=5_t=1.tiff"  "image_z=5_t=2.tiff"  "image_z=5_t=3.tiff"     "image_z=5_t=29.tiff"  "image_z=5_t=30.tiff"
```

and then

```julia
julia> buf = load(first(filenames));

julia> img = load_series(load!, filenames, buf)
```

would create a 4-dimensional output. `load!` would ideally load directly into its first argument,
but could be defined as

```julia
load!(dest, filename) = copyto!(dest, load(filename))
```

if needed.
"""
@noinline function load_series(f::F, filenames::AbstractArray{<:AbstractString}, buffer::AbstractArray) where F
    return MultifileArray(filenames, buffer, f)
end

"""
    A = load_chunked(lazyloader, filenames)

Load an array from chunks stored in files in `filenames`. `filenames` must be shaped so that it is "extended"
along the dimension of concatenation.

When each chunk has the same size and is equivalent to a single slice of the final array, [`load_series`](@ref)
may yield better performance.

# Examples

Suppose you have 2 files, `myimage_1.tiff` and `myimage_2.tiff`, with the first storing 1000 two-dimensional
images and the second storing 555 images of the same shape. Then you can load a contiguous 3d array with

```julia
julia> julia> filenames = reshape(["myimage_1.tiff", "myimage_2.tiff"], (1, 1, 2))
1×1×2 Array{String, 3}:
[:, :, 1] =
 "myimage_1.tiff"

[:, :, 2] =
 "myimage_2.tiff"

julia> img = load_chunked(fn -> load(fn; mmap=true), filenames);

julia> size(img)
(512, 512, 1555)
```

In the [TiffImages](https://github.com/tlnagy/TiffImages.jl) package, `mmap=true` allows you to "virtually" load the data by memory-mapping, supporting arrays much larger than computer memory.

!!! note
    `load_chunked` requires that you manually load the [BlockArrays](https://github.com/JuliaArrays/BlockArrays.jl) package.
"""
function load_chunked end

function __init__()
    @require BlockArrays = "8e7c35d0-a365-5155-bbbb-fb81a777f24e" include("mortar.jl")
end

end
