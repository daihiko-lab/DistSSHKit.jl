#!/usr/bin/env julia
# DistSSHKit driver script: each worker flips a coin many times and reports
# how many landed on heads.
# After Pkg.add:  julia --project=. -m DistSSHKit demo install
# Then run:       julia --project=. -m DistSSHKit runner --local 2 demos/coin_flip.jl

using Distributed

# Called before workers start. Must set ENV["DISTRIBUTED_OUTPUT_DIR"].
function init_output_dir!(_script_args::Vector{String})
    dir = joinpath(@__DIR__, "output")
    mkpath(dir)
    ENV["DISTRIBUTED_OUTPUT_DIR"] = dir
    return dir
end

# Called after workers are ready.
function main()
    # Optional args: flips_per_task (default 100), n_tasks (default 4).
    flips_per_task = if length(ARGS) >= 1
        parse(Int, ARGS[1])
    else
        100
    end
    n_tasks = if length(ARGS) >= 2
        parse(Int, ARGS[2])
    else
        4
    end

    # pmap distributes the n_tasks coin-flipping jobs across the workers.
    heads_counts = pmap(_ -> count(<(0.5), rand(flips_per_task)), 1:n_tasks)

    println("Heads per task: ", heads_counts)
end
