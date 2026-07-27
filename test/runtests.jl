#!/usr/bin/env julia
# SSHRunner unit tests (optional; not required in every host application).
# From the application repo root (when this tree lives under `SSHRunner/`):
#   julia --project=. SSHRunner/test/runtests.jl
# From a standalone kit checkout (this directory as the active project):
#   julia --project=. -e 'using Pkg; Pkg.test()'
#
# Maintainer checks: README.md ("Local verification").
#   jetls check demos/*.jl src/SSHRunner.jl src/runner.jl src/setup.jl src/suggest_workers.jl test/*.jl test/fixtures/*.jl

using Test

isdefined(@__MODULE__, :SSHRunner) || include(joinpath(@__DIR__, "..", "src", "SSHRunner.jl"))
using .SSHRunner

include(joinpath(@__DIR__, "test_runner_log_common.jl"))

const _TEST_FILES = (
    "test_path_helpers.jl",
    "test_main_dispatch.jl",
    "test_demo_cli.jl",
    "test_host_project_toml.jl",
    "test_runner_args.jl",
    "test_runner_smoke.jl",
    "test_runner_log_script.jl",
    "test_runner_log_module.jl",
    "test_demos.jl",
    "test_pkg_add_smoke.jl",
)

@testset "SSHRunner" verbose=true begin
    for file in _TEST_FILES
        println("▸ ", file)
        include(joinpath(@__DIR__, file))
    end
end
