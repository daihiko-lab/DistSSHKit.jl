"""
DistSSHKit — shared utilities for `runner.jl`, `setup.jl`, and `suggest_workers.jl`
(paths, logging, SSH/git, remote resource probes, remote path resolution).

Scripts load this module via a relative `include` and then `using .DistSSHKit`.
When vendored as a registered package, replace with `using DistSSHKit`.

This top-level file is the entry point only: `module`/`export`, the `@__DIR__`-based
version constant, wiring (`include`) for the implementation files under `DistSSHKit/`,
and the CLI dispatch (`(@main)`) for `julia -m DistSSHKit ...`. Implementation:
- `DistSSHKit/display.jl` — path display helpers, console/log output, `TeeIO`
- `DistSSHKit/remote.jl`  — SSH/git/resource probes, remote path resolution, result collection
- `DistSSHKit/demos.jl`   — bundled demo discovery and the `demo install`/`demo list` CLI

Runner-specific logic (CLI args, preflight checks, distributed orchestration) lives under
`src/runner/` and is included into `Main` by `runner.jl`.

Anything that resolves paths via `@__DIR__` (kit root, vendored `Project.toml` version,
CLI script dispatch) stays in this top-level file, since `@__DIR__` inside an `include`d
file would resolve relative to that file's own directory, not `src/`.
"""
module DistSSHKit

using Dates

export LOG_FILE_HANDLE, OUTPUT_WIDTH, SSH_OPTS, DIST_SSH_KIT_VERSION, TeeIO
export build_ssh_opts, clone_url_from_local_origin
export close_log_file, collect_tree_remote_files_ssh, default_remote_project_path, detect_julia_path
export display_path, distributed_collect_root_dirs, fail, get_local_git_hash, get_local_resources
export get_remote_git_hash, get_remote_nproc, get_remote_total_gb, init_log_file
export normalize_git_clone_url, ok, dist_ssh_kit_version
export print_err, print_header, print_info, print_ok, print_separator, print_warn
export demo_script, demos_dir, install_demos, list_demos
export project_package_name, remote_path_for_ssh_collect, resolve_pkg_project_dir
export runner_kit_project_root
export resolve_remote_project_root, short_path, use_colors, warn
export write_both, writeln_both

# =============================================================================
# Implementation (paths/output, SSH/git/remote, runner CLI)
# =============================================================================

include("DistSSHKit/display.jl")
include("DistSSHKit/remote.jl")
include("DistSSHKit/demos.jl")

# =============================================================================
# Vendored kit version (from kit `Project.toml`)
# =============================================================================
# NOTE: `@__DIR__` here resolves to `src/` (this file's own directory) — keep any
# `@__DIR__`-based path resolution in this top-level file, not in an included file.

"""Read `version = "x.y.z"` from `path` (`Project.toml`); return `nothing` if missing or invalid."""
function _project_toml_version(path::AbstractString)::Union{Nothing,VersionNumber}
    p = String(path)
    isfile(p) || return nothing
    try
        m = match(r"version\s*=\s*\"([^\"]+)\"", read(p, String))
        m === nothing && return nothing
        cap = m.captures[1]
        return cap isa AbstractString ? VersionNumber(String(cap)) : nothing
    catch
        return nothing
    end
end

const _DIST_SSH_KIT_PROJECT_TOML = joinpath(@__DIR__, "..", "Project.toml")

"""Semantic version of this vendored kit (from kit `Project.toml`)."""
const DIST_SSH_KIT_VERSION = something(
    _project_toml_version(_DIST_SSH_KIT_PROJECT_TOML),
    v"0.0.0",
)

dist_ssh_kit_version()::VersionNumber = DIST_SSH_KIT_VERSION

# =============================================================================
# CLI entry points (for `Pkg.add`/`Pkg.develop` users)
# =============================================================================
# Each entry point delegates to the vendored CLI scripts in `src/` (`runner.jl`,
# `setup.jl`, …) unchanged rather than duplicating logic here.
#
# Primary workflow (no submodule/Pkg Apps needed):
#   julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/daihiko-lab/SSHRunner.jl.git", rev="vX.Y.Z")'
#   julia --project=. -m DistSSHKit runner --local 2 script.jl

const _KIT_ROOT = dirname(@__DIR__)

const _KIT_CLI_LOADED = Set{String}()
const _KIT_CLI_SCRIPTS = ("runner.jl", "setup.jl", "suggest_workers.jl")

const _KIT_CLI_MAIN = Dict(
    "runner.jl" => :runner_main,
    "setup.jl" => :setup_main,
    "suggest_workers.jl" => :suggest_workers_main,
)

function _kit_cli_run_entry(script_base::String)::Cint
    sym = get(_KIT_CLI_MAIN, script_base, nothing)
    sym === nothing && return 0
    fn = getfield(Main, sym)
    if script_base == "runner.jl"
        return Base.invokelatest(fn)
    end
    Base.invokelatest(fn)
    return 0
end

"""Run a kit CLI script in `src/` (`runner.jl`, `setup.jl`, …) with `ARGS` set."""
function _run_kit_cli_script(script_name::AbstractString, args::Vector{String})::Cint
    haskey(ENV, "DISTRIBUTED_PROJECT_ROOT") || (ENV["DISTRIBUTED_PROJECT_ROOT"] = pwd())
    # `args` may alias `ARGS` (the app launcher can pass `ARGS` directly).
    args_snapshot = collect(String, args)
    empty!(ARGS)
    append!(ARGS, args_snapshot)
    script_path::String = if isabspath(script_name)
        String(script_name)
    else
        joinpath(@__DIR__, String(script_name))
    end
    script_base = basename(script_path)
    prev_include = get(ENV, "DIST_SSH_KIT_CLI_INCLUDE", nothing)
    ENV["DIST_SSH_KIT_CLI_INCLUDE"] = "1"
    try
        if script_base in _KIT_CLI_SCRIPTS
            if !(script_base in _KIT_CLI_LOADED)
                Core.include(Main, script_path)
                push!(_KIT_CLI_LOADED, script_base)
            end
            return _kit_cli_run_entry(script_base)
        end
        Core.include(Main, script_path)
        return 0
    finally
        if prev_include === nothing
            delete!(ENV, "DIST_SSH_KIT_CLI_INCLUDE")
        else
            ENV["DIST_SSH_KIT_CLI_INCLUDE"] = prev_include
        end
    end
end

"""
    runner(args::Vector{String}=copy(ARGS))

Run `runner.jl` (distributed runs) with `args`. Backs `julia -m DistSSHKit runner ...`
(see [`(@main)`](@ref)), which is the recommended way to call this for `Pkg.add`/
`Pkg.develop` users who don't vendor the kit's CLI scripts directly. Also callable
directly via `-e` if you need to avoid `-m`:

    julia --project=. -e 'using DistSSHKit; DistSSHKit.runner()' -- --local 2 script.jl
"""
runner(args::Vector{String}=copy(ARGS))::Cint = _run_kit_cli_script("runner.jl", args)

"""
    setup(args::Vector{String}=copy(ARGS))

Run `setup.jl` (clone / sync / cleanup) with `args`. See [`runner`](@ref).
"""
setup(args::Vector{String}=copy(ARGS))::Cint = _run_kit_cli_script("setup.jl", args)

"""
    suggest_workers(args::Vector{String}=copy(ARGS))

Run `suggest_workers.jl` (worker-count hints) with `args`. See [`runner`](@ref).
"""
suggest_workers(args::Vector{String}=copy(ARGS))::Cint = _run_kit_cli_script("suggest_workers.jl", args)

"""
    (@main)(args::Vector{String}=copy(ARGS))

Subcommand dispatch for `julia -m DistSSHKit SUBCOMMAND ...` (Julia 1.12+, no
`Pkg Apps` install needed — works for any `Pkg.add`/`Pkg.develop`ed package):

    julia --project=. -m DistSSHKit runner --local 2 script.jl
    julia --project=. -m DistSSHKit demo install
    julia --project=. -m DistSSHKit runner --local 2 demos/param_sweep.jl
    julia --project=. -m DistSSHKit setup --clone host1 host2
    julia --project=. -m DistSSHKit suggest-workers --local host1 host2
"""
function (@main)(args::Vector{String}=copy(ARGS))::Cint
    isempty(args) && (println(stderr, "Usage: julia -m DistSSHKit {runner|demo|setup|suggest-workers} [args...]"); return 1)
    subcommand, rest = args[1], args[2:end]
    if subcommand == "runner"
        return runner(rest)
    elseif subcommand == "demo"
        return demo(rest)
    elseif subcommand == "setup"
        return setup(rest)
    elseif subcommand in ("suggest-workers", "suggest_workers")
        return suggest_workers(rest)
    else
        println(stderr, "Unknown subcommand: $subcommand (expected runner|demo|setup|suggest-workers)")
        return 1
    end
end

end # module DistSSHKit
