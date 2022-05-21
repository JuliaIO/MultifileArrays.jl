module MultifileArrays

using SparseArrays   # only for ambiguity resolution

export select_series, load_series

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
Base.copyto!(dest::SparseVector, src::SubArray{T,1,<:MultifileArray}) where {T,N} =
    _copyto!(dest, src)


## User-level API

function select_series(filepattern::Regex; dir=pwd())
    filenames = String[]
    order = Int[]
    for filename in readdir(dir)
        m = match(filepattern, filename)
        m === nothing && continue
        push!(filenames, joinpath(dir, filename))
        push!(order, (parse.(Int, m.captures)...,))
    end
    isempty(filenames) && throw(ArgumentError("no files in $dir matched $filepattern"))
    p = sortperm(order)
    return filenames[p]
end

"""
    filenames = select_series(filepattern; dir=pwd())

Create a vector of filenames from `filepattern`. `filepattern` may be a string containing a `*` character
(which is treated as a wildcard match), or a regular expression capturing a digit-substring.
In either case, the `*`/`capture` extracts an integer that determines file order.
"""
function select_series(filepattern::AbstractString; kwargs...)
    rex = Regex(join(split(filepattern, '*'), "(\\d+)"))
    return select_series(rex; kwargs...)
end

"""
    A = load_series(f, filepattern; dir=pwd())

Create a lazily-loaded array `A` from a set of files. `f(filename)` should create an array from the `filename`,
and `filepattern` is a pattern matching the names of the desired files. The file names should have a numeric
portion that indicates ordering; ordering is numeric rather than alphabetical, so left-padding with zeros is optional.

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

end
