module MultifileArraysBlockArrays

using BlockArrays: mortar
using BlockArrays.ArrayLayouts: LayoutArray
using MultifileArrays: MultifileArrays, MultifileArray

Base.copyto!(dest::LayoutArray, src::SubArray{T,N,<:MultifileArray}) where {T,N} =
    _copyto!(dest, src)
Base.copyto!(dest::SubArray{<:Any,N,<:LayoutArray}, src::SubArray{T,N,<:MultifileArray}) where {T,N} =
    _copyto!(dest, src)

MultifileArrays.load_chunked(lazyloader, filenames) = mortar([lazyloader(fn) for fn in filenames])

end # module
