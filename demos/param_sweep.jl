#!/usr/bin/env julia
# SSHRunner driver script: sweep a parameter across workers.
#   julia --project=. -m SSHRunner runner --local 4 demos/param_sweep.jl
#   julia --project=. -m SSHRunner runner HOST1 HOST2 demos/param_sweep.jl

using Distributed

function init_output_dir!(_script_args::Vector{String})
    dir = joinpath(@__DIR__, "output")
    mkpath(dir)
    ENV["DISTRIBUTED_OUTPUT_DIR"] = dir
    return dir
end

function main()
    # Sweep `param` over 1:8 and compute `param^2` for each; `pmap` distributes
    # the 8 values across the available workers.
    params = 1:8
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
