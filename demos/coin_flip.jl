#!/usr/bin/env julia
# SSHRunner driver script: each task flips a coin many times and reports the count.
#   julia --project=. -m SSHRunner runner --local 2 demos/coin_flip.jl
#   julia --project=. -m SSHRunner runner HOST1 HOST2 demos/coin_flip.jl

using Distributed

function init_output_dir!(_script_args::Vector{String})
    dir = joinpath(@__DIR__, "output")
    mkpath(dir)
    ENV["DISTRIBUTED_OUTPUT_DIR"] = dir
    return dir
end

function main()
    flips_per_task = 100
    # Each of the 4 tasks flips a coin `flips_per_task` times and counts how many
    # landed heads (`rand() < 0.5`). `pmap` sends one task to each worker.
    heads_counts = pmap(_ -> count(<(0.5), rand(flips_per_task)), 1:4)
    println(heads_counts)
end
