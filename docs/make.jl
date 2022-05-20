using LazyMultifileArrays
using Documenter

DocMeta.setdocmeta!(LazyMultifileArrays, :DocTestSetup, :(using LazyMultifileArrays); recursive=true)

makedocs(;
    modules=[LazyMultifileArrays],
    authors="Tim Holy <tim.holy@gmail.com> and contributors",
    repo="https://github.com/JuliaIO/LazyMultifileArrays.jl/blob/{commit}{path}#{line}",
    sitename="LazyMultifileArrays.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaIO.github.io/LazyMultifileArrays.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaIO/LazyMultifileArrays.jl",
    devbranch="main",
)
