using MultifileArrays
using Documenter

DocMeta.setdocmeta!(MultifileArrays, :DocTestSetup, :(using MultifileArrays); recursive=true)

makedocs(;
    modules=[MultifileArrays],
    authors="Tim Holy <tim.holy@gmail.com> and contributors",
    repo="https://github.com/JuliaIO/MultifileArrays.jl/blob/{commit}{path}#{line}",
    sitename="MultifileArrays.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaIO.github.io/MultifileArrays.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaIO/MultifileArrays.jl",
    devbranch="main",
)
