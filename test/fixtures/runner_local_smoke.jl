# Minimal driver for `runner.jl --local` smoke tests (spawned as a subprocess).
using Distributed

function main()
    nw = nworkers()
    nw >= 2 || error("expected >= 2 workers, got ", nw)
    println("PRK_RUNNER_SMOKE_OK nw=", nw)
end
