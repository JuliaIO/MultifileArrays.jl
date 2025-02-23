using MultifileArrays
using BlockArrays
using FileIO
using FixedPointNumbers
using ColorTypes
using Test

@testset "MultifileArrays.jl" begin
    @testset "ambiguities" begin
        if Base.VERSION >= v"1.7.0"
            @test isempty(detect_ambiguities(MultifileArrays))
        end
    end

    mktempdir() do path
        for i = 1:12
            save(joinpath(path, "myimage_$i.tiff"), fill(Gray(reinterpret(N0f8, UInt8(i))), 5, 7))
        end
        write(joinpath(path, "junk.txt"), "blah blah")
        fls = select_series("myimage_*.tiff"; dir=path)
        @test fls[2] == joinpath(path, "myimage_2.tiff")
        @test fls[11] == joinpath(path, "myimage_11.tiff")
        fls2 = select_series(joinpath(path, "myimage_*.tiff"))
        @test fls2 == fls
        img = load_series(load, "myimage_*.tiff"; dir=path)
        @test size(img) == (5, 7, 12)
        for i = 1:12
            @test all(==(reinterpret(N0f8, UInt8(i))), img[:,:,i])
        end
    end

    mktempdir() do path
        encode(z, t) = Gray(reinterpret(N0f16, UInt16(z) | UInt16(t) << 8))
        load!(buffer, fl) = copyto!(buffer, load(fl))

        for z = 1:4, t = 1:5
            save(joinpath(path, "myimage_z=$(z)_t=$(t).tiff"), fill(encode(z, t), 5, 7))
        end
        fls = permutedims(reshape(readdir(path; join=true), 5, 4), (2, 1))
        img = load_series(load!, fls, zeros(N0f16, 5, 7))
        @test size(img) == (5, 7, 4, 5)
        for z = 1:4, t = 1:5
            @test all(==(encode(z, t)), img[:,:,z,t])
        end
        img2 = load_series(load, joinpath(path,"myimage_z=*_t=*.tiff"))
        @test size(img2) == (5, 7, 4, 5)
        for z = 1:4, t = 1:5
            @test all(==(encode(z, t)), img2[:,:,z,t])
        end
    end

    mktempdir() do path
        fns = [joinpath(path, "myimage_1.tiff"), joinpath(path, "myimage_2.tiff")]
        img1, img2 = rand(Gray{N0f8}, 8, 7, 10), rand(Gray{N0f8}, 8, 7, 4)
        save(fns[1], img1)
        save(fns[2], img2)
        filenames = reshape(fns, (1, 1, 2))
        img = load_chunked(fn -> load(fn; mmap=true), filenames)
        @test size(img) == (8, 7, 14)
        @test img[:,:,1:10] == img1
        @test img[:,:,11:end] == img2
        # there is an issue with the directory cleanup here, since the files are still open
    end
end
