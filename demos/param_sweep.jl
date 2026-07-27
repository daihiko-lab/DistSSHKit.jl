#!/usr/bin/env julia
# DistSSHKit driver script: run the same computation for many parameter values,
# spread across workers, and save all the results to one CSV file.
# After Pkg.add:  julia --project=. -m DistSSHKit demo install
# Then run:       julia --project=. -m DistSSHKit runner --local 4 demos/param_sweep.jl
#
# Output: demos/output/sweep_results.csv

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
    # Optional arg: sweep size (default 8), e.g. `... param_sweep.jl 4`.
    n = if length(ARGS) >= 1
        parse(Int, ARGS[1])
    else
        8
    end
    params = 1:n

    # pmap distributes the n param^2 computations across the workers.
    results = pmap(param -> param^2, params)

    out_path = joinpath(ENV["DISTRIBUTED_OUTPUT_DIR"], "sweep_results.csv")
    open(out_path, "w") do io
        println(io, "param,result")
        for (param, result) in zip(params, results)
            println(io, param, ",", result)
        end
    end
    println("wrote ", out_path)
end
