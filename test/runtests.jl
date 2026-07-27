#!/usr/bin/env julia
# SSHRunner unit tests (optional; not required in every host application).
# From the application repo root (when this tree lives under `SSHRunner/`):
#   julia --project=. SSHRunner/test/runtests.jl
# From a standalone kit checkout (this directory as the active project):
#   julia --project=. test/runtests.jl

using Test

isdefined(@__MODULE__, :SSHRunner) || include(joinpath(@__DIR__, "..", "src", "SSHRunner.jl"))
using .SSHRunner

include(joinpath(@__DIR__, "test_ssh_runner.jl"))
include(joinpath(@__DIR__, "test_runner_args.jl"))
include(joinpath(@__DIR__, "test_runner_smoke.jl"))
include(joinpath(@__DIR__, "test_pkg_add_smoke.jl"))
