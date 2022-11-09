using .BlockArrays: mortar
using .BlockArrays.ArrayLayouts: LayoutArray

Base.copyto!(dest::LayoutArray, src::SubArray{T,N,<:MultifileArray}) where {T,N} =
    _copyto!(dest, src)
Base.copyto!(dest::SubArray{<:Any,N,<:LayoutArray}, src::SubArray{T,N,<:MultifileArray}) where {T,N} =
    _copyto!(dest, src)

load_chunked(lazyloader, filenames) = mortar([lazyloader(fn) for fn in filenames])
