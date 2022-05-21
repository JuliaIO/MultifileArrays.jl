using MultifileArrays
using Test

@testset "MultifileArrays.jl" begin
    @testset "ambiguities" begin
        @test isempty(detect_ambiguities(MultifileArrays))
    end
    # Write your tests here.
end
