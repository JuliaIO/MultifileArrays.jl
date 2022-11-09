```@meta
CurrentModule = MultifileArrays
```

# MultifileArrays

[MultifileArrays](https://github.com/JuliaIO/MultifileArrays.jl) implements "lazy concatenation" of file data. The primary function, [`load_series`](@ref), will load data from disk on-demand and store "slices" in a temporary buffer. This allows you treat a series of files as if they are a large contiguous array.

Further examples are described in the [API](@ref) section, but a simple demo using a directory `dir` with a bunch of PNG files might be

```julia
julia> using MultifileArrays, FileIO

julia> img = load_series(load, "myimage_*.png"; dir)
```

## Performance tips

While MultifileArrays is convenient, there are some performance caveats to keep in mind:

- to reduce the number of times that a file needs to be (re)loaded from disk, iteration over the resulting array is best done in a manner consistent with the file-by-file slicing.
- operations than can be performed "slice at a time" (e.g., visualization with ImageView) are even more optimized, as they bypass the need to check whether the supplied slice-index corresponds to the currently loaded file when accessing individual elements of the array.

For uncompressed data, alternative approaches that exploit [memory-mapping](https://en.wikipedia.org/wiki/Memory-mapped_file) may yield better performance. The [StackViews](https://github.com/JuliaArrays/StackViews.jl) package allows you to "glue" such arrays together.

## API

```@index
```

```@autodocs
Modules = [MultifileArrays]
```
