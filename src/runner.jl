#!/usr/bin/env julia
"""
Distributed Runner
==================
Add local and/or remote SSH worker processes, then run a Julia script with distributed pmap support.

NOTE: This uses Distributed.jl (multi-process), not multi-threading.
      - pmap/remotecall work across separate Julia processes
      - Each worker is an independent process with its own memory
      - For multi-threading within a single process, use Julia's -t option directly

Workflow:
  1. Verify git hash matches across all hosts (skip with --skip-hash-check)
  2. Clean up stale worker processes (local + remote)
  3. Check memory capacity (after cleanup for accurate readings)
  4. Add local/remote worker processes
  5. Initialize workers: activate project, load package
  6. Run the target script
  7. Collect new result files from remote hosts back to local

Usage (via `Pkg.add`/`Pkg.develop`):
  # Remote hosts only (master process on local, workers on remotes)
  julia --project=. -m SSHRunner runner host1:10 host2:10 script.jl --args

  # Local + remote (9 local workers + 20 remote = 29 total worker processes)
  julia --project=. -m SSHRunner runner --local 9 host1:10 host2:10 script.jl --args

  # Local only (9 worker processes)
  julia --project=. -m SSHRunner runner --local 9 script.jl --args

Host specification:
  hostname        Use default worker count (1 or --workers N)
  hostname:N      Use N workers on this host

Options:
  -l, --local N         Number of local worker processes to add (default: 0)
  -w, --workers N       Default worker count for hosts without explicit :N
  --julia PATH          Julia executable path for remote hosts (default: auto-detect)
  --skip-hash-check     Skip git commit verification (not recommended)
  --no-log              Do not write console output to a log file
  --log-dir PATH        Log output directory (default: script's output dir, or <script_dir>/results)
  --package NAME        Load this module on workers instead of `name` from Project.toml
  --collect-missing ROOT HOST...   files under ROOT missing locally only (by relative path)
  --collect-overwrite ROOT HOST... rsync-merge whole tree under ROOT (overwrite same-named files)
  --collect-tree / --collect-tree-sync  aliases (--collect-missing / --collect-overwrite)
  -h, --help            Show help

Output:
  Console output is written to <log_dir>/runner_<timestamp>.log.
  Default log dir is determined by the script (via ENV["DISTRIBUTED_OUTPUT_DIR"] set by init_output_dir!),
  then --output-dir from script_args, then <script_dir>/results as last fallback.
  Use --log-dir to override. Use --no-log to disable.

Environment variables:
  DISTRIBUTED_SSH_OPTS       Custom SSH options (space-separated)
  DISTRIBUTED_COLLECT_DIRS   Colon-separated dirs to rsync after run (repo-relative or abs); see SSHRunner.distributed_collect_root_dirs
  JULIA_DISTRIBUTED_EXE      Default Julia path for remote hosts

Prerequisites:
  - SSH key authentication to all remote hosts
  - Same project path on all machines (e.g., ~/projects/MyModel.jl)
  - Same git commit (checked automatically)
  - Julia installed on remote hosts (auto-detected in common locations)

Example (full workflow):
  # 1. Sync code to remotes
  julia --project=. -m SSHRunner setup --sync host1 host2

  # 2. Run a driver script with 29 worker processes (9 local + 10 + 10 remote)
  julia --project=. -m SSHRunner runner --local 9 host1:10 host2:10 \\
      scripts/jobs.jl --config configs/cell.json

See also: `julia -m SSHRunner setup --help`, README.md
"""

using Distributed
using Dates
using Pkg

# When loaded via `Pkg.add`/`Pkg.develop` (real package, e.g. through `SSHRunner.runner()`),
# `SSHRunner` is already bound in this module (`Main`); skip the vendored/script re-include.
isdefined(@__MODULE__, :SSHRunner) || include(joinpath(@__DIR__, "SSHRunner.jl"))
using .SSHRunner

const PROJECT_ROOT = get(ENV, "DISTRIBUTED_PROJECT_ROOT") do
    runner_kit_project_root(@__DIR__)
end

include(joinpath(@__DIR__, "runner", "_common.jl"))
include(joinpath(@__DIR__, "runner", "args.jl"))
include(joinpath(@__DIR__, "runner", "checks.jl"))
include(joinpath(@__DIR__, "runner", "collect.jl"))
include(joinpath(@__DIR__, "runner", "workers.jl"))
include(joinpath(@__DIR__, "runner", "init.jl"))
include(joinpath(@__DIR__, "runner", "results.jl"))

show_help() = println(runner_help_text())

function runner_main()::Cint
    parsed = parse_runner_args(ARGS)

    if parsed.help
        show_help()
        return 0
    end

    if parsed.collect_root !== nothing && parsed.collect_hosts !== nothing
        ok = runner_collect_tree(
            parsed.collect_root::String,
            parsed.collect_hosts::Vector{String};
            merge=something(parsed.collect_overwrite, false),
        )
        return ok ? 0 : 1
    end

    if parsed.script_path === nothing
        show_help()
        return 1
    end

    hosts = parsed.hosts
    root_disp = abspath(expanduser(String(PROJECT_ROOT)))
    script_path = parsed.script_path::String
    script_args = parsed.script_args
    local_workers = parsed.local_workers
    default_workers = parsed.default_workers
    julia_exe = parsed.julia
    skip_hash_check = parsed.skip_hash_check
    enable_log = parsed.enable_log
    log_dir = parsed.log_dir
    explicit_package = parsed.explicit_package

    host_names = [h[1] for h in hosts]

    if !isabspath(script_path)
        script_path = abspath(script_path)
    end

    if !isfile(script_path)
        error("Script not found: $script_path")
    end

    script_dir = dirname(script_path)
    proj_dir = resolve_pkg_project_dir(script_dir)

    include(script_path)
    if isdefined(Main, :init_output_dir!)
        @invokelatest Main.init_output_dir!(script_args)
    end

    if enable_log
        resolved_log_dir = log_dir
        if resolved_log_dir === nothing
            resolved_log_dir = get(ENV, "DISTRIBUTED_OUTPUT_DIR", nothing)
        end
        if resolved_log_dir === nothing
            for j in 1:length(script_args)-1
                if script_args[j] == "--output-dir"
                    resolved_log_dir = script_args[j+1]
                    break
                end
            end
        end
        if resolved_log_dir === nothing
            resolved_log_dir = joinpath(script_dir, "results")
        end
        init_log_file(String(resolved_log_dir); prefix="runner", path_anchor=root_disp)
        atexit(close_log_file)
    end

    print_header("Distributed Runner")
    writeln_both("")
    writeln_both("Script: $(display_path(script_path, root_disp))")
    writeln_both("Args: $(join(script_args, " "))")
    proj_disp = let s = display_path(proj_dir, root_disp)
        s == "." ? basename(abspath(String(proj_dir))) : s
    end
    writeln_both("Project: $(proj_disp)")
    writeln_both("SSHRunner: $(ssh_runner_version())")
    app_git = get_local_git_hash(proj_dir; short=8)
    writeln_both("Application git (project dir): $(app_git === nothing ? "unavailable" : app_git)")
    writeln_both("")

    if !isempty(host_names)
        if skip_hash_check
            writeln_both("Git hash check: skipped (--skip-hash-check)")
            writeln_both("")
        else
            writeln_both("Checking git hashes...")
            ok, mismatches = check_git_hashes(host_names, PROJECT_ROOT)
            writeln_both("")
            if !ok
                print_err("ERROR: ", bold=true)
                writeln_both("Git hash mismatch on $(join(mismatches, ", "))")
                writeln_both("")
                writeln_both("To sync, run:")
                print_info("  julia --project=. -m SSHRunner setup --sync $(join(mismatches, " "))\n")
                writeln_both("")
                writeln_both("Or skip check (not recommended):")
                print_warn("  --skip-hash-check\n")
                writeln_both("")
                return 1
            end
        end
    end

    cleanup_stale_workers!(hosts)

    if local_workers > 0 || !isempty(hosts)
        check_memory_capacity(local_workers, hosts, default_workers) || return 0
    end

    successful_hosts = add_runner_workers!(
        hosts, local_workers, default_workers, julia_exe, proj_dir, script_dir,
    )
    wait_for_worker_connections!()
    cleanup_workers = register_worker_cleanup!(successful_hosts)

    init_runner_workers!(proj_dir, explicit_package, root_disp)

    empty!(ARGS)
    append!(ARGS, script_args)

    ENV["DISTRIBUTED_RUNNER"] = "1"
    skip_collect = get(ENV, "DISTRIBUTED_SKIP_COLLECT", "") == "1"
    sentinel_name = place_runner_sentinels!(successful_hosts, script_dir, skip_collect)

    run_driver_script!(enable_log, cleanup_workers)

    collect_runner_results!(successful_hosts, script_dir, sentinel_name, skip_collect, root_disp)
    return 0
end

if get(ENV, "SSHRUNNER_KIT_CLI_INCLUDE", "") != "1" &&
   !isempty(PROGRAM_FILE) &&
   abspath(PROGRAM_FILE) == abspath(@__FILE__)
    exit(runner_main())
end
