#!/usr/bin/env julia
# Minimal driver compatible with SSHRunner/src/runner.jl: copy beside your code and
# replace `main()` with your workload. `Distributed` and `Dates` are stdlib, so they're
# available without adding them to your Project.toml.

using Dates
using Distributed

"""Parent of `SSHRunner/` when embedded; otherwise the kit repo root."""
function _data_anchor_dir()::String
    kit_root = dirname(@__DIR__)
    pt = joinpath(kit_root, "Project.toml")
    isfile(pt) || return abspath(kit_root)
    m = match(r"name\s*=\s*\"([^\"]+)\"", read(pt, String))
    if m !== nothing && strip(String(m.captures[1])) == "SSHRunner"
        return abspath(joinpath(kit_root, ".."))
    end
    return abspath(kit_root)
end

function init_output_dir!(args::Vector{String})
    _ = args
    root = joinpath(_data_anchor_dir(), "data", "runner_template", Dates.format(now(), "yyyymmdd_HHMMSS"))
    mkpath(root)
    ENV["DISTRIBUTED_OUTPUT_DIR"] = root
    return root
end

function main()
    n = nworkers()
    println("script_template: ", n, " worker process(es) (+ master)")
    n == 0 && error("No workers; launch with e.g. `julia -m SSHRunner runner --local 2 …`")
    ids = pmap(_ -> myid(), 1:min(n, 8))
    println("  sample myid() from pmap: ", ids)
end

if abspath(PROGRAM_FILE) == @__FILE__
    println("For distributed runs use:")
    println("  julia --project=. -m SSHRunner runner --local 2 script_template.jl")
end
