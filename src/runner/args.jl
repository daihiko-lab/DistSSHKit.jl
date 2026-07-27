# Runner CLI argument parsing and help text.

function _parse_host_workers_spec(spec::String)
    if contains(spec, ':')
        parts = split(spec, ':', limit=2)
        host = String(parts[1])
        workers = parse(Int, parts[2])
        return (host, workers)
    else
        return (spec, nothing)
    end
end

function parse_runner_args(args::Vector{String})
    local_workers = 0
    default_workers = nothing
    julia_exe = nothing
    skip_hash_check = false
    enable_log = true
    log_dir = nothing
    explicit_package = nothing
    hosts = Tuple{String,Union{Int,Nothing}}[]
    script_path = nothing
    script_args = String[]

    i = 1
    while i <= length(args)
        arg = String(args[i])

        if (arg == "--local" || arg == "-l") && i < length(args)
            local_workers = parse(Int, args[i+1])
            i += 2
        elseif (arg == "--workers" || arg == "-w") && i < length(args)
            default_workers = parse(Int, args[i+1])
            i += 2
        elseif arg == "--julia" && i < length(args)
            julia_exe = args[i+1]
            i += 2
        elseif arg == "--skip-hash-check" || arg == "--no-hash-check"
            skip_hash_check = true
            i += 1
        elseif arg == "--no-log"
            enable_log = false
            i += 1
        elseif arg == "--log-dir" && i < length(args)
            log_dir = args[i+1]
            i += 2
        elseif arg == "--package" && i < length(args)
            p = String(strip(args[i+1]))
            explicit_package = isempty(p) ? nothing : p
            i += 2
        elseif arg == "--collect" || arg == "--collect-sync"
            throw(ArgumentError(
                "$(arg) was removed; use --collect-missing ROOT HOST... or --collect-overwrite ROOT HOST...",
            ))
        elseif arg == "--collect-missing" ||
                arg == "--collect-overwrite" ||
                arg == "--collect-tree" ||
                arg == "--collect-tree-sync"
            flag = arg
            merge = flag == "--collect-overwrite" || flag == "--collect-tree-sync"
            !isempty(hosts) &&
                throw(ArgumentError(
                    "host specs before $(flag) are not supported; use $(flag) ROOT HOST..."))
            tail = args[i+1:end]
            isempty(tail) && throw(ArgumentError("`$(flag)` requires ROOT HOST [HOST...]"))
            for a in tail
                if startswith(a, '-') && length(a) > 1
                    throw(ArgumentError(
                        "`$(flag)` arguments cannot include options like $(repr(a)); put flags before $(flag)"))
                end
            end
            tree_root = String(abspath(expanduser(String(tail[1]))))
            tree_hosts = String[_parse_host_workers_spec(String(x))[1] for x in tail[2:end]]
            isempty(tree_hosts) && throw(ArgumentError("`$(flag)` requires at least one HOST after ROOT"))
            if julia_exe === nothing
                env_val = get(ENV, "JULIA_DISTRIBUTED_EXE", "auto")
                julia_exe = env_val == "auto" ? nothing : env_val
            elseif julia_exe == "auto"
                julia_exe = nothing
            end
            return (
                local_workers=local_workers,
                default_workers=default_workers,
                julia=julia_exe,
                skip_hash_check=skip_hash_check,
                enable_log=enable_log,
                log_dir=log_dir,
                explicit_package=explicit_package,
                hosts=Tuple{String,Union{Int,Nothing}}[],
                script_path=nothing,
                script_args=String[],
                collect_root=tree_root,
                collect_hosts=tree_hosts,
                collect_overwrite=merge,
                help=false,
            )
        elseif arg == "--help" || arg == "-h"
            return (
                local_workers=0,
                default_workers=nothing,
                julia=nothing,
                skip_hash_check=false,
                enable_log=true,
                log_dir=nothing,
                explicit_package=nothing,
                hosts=Tuple{String,Union{Int,Nothing}}[],
                script_path=nothing,
                script_args=String[],
                collect_root=nothing,
                collect_hosts=nothing,
                collect_overwrite=nothing,
                help=true,
            )
        elseif endswith(arg, ".jl")
            script_path = arg
            script_args = args[i+1:end]
            break
        else
            push!(hosts, _parse_host_workers_spec(arg))
            i += 1
        end
    end

    if julia_exe === nothing
        env_val = get(ENV, "JULIA_DISTRIBUTED_EXE", "auto")
        julia_exe = env_val == "auto" ? nothing : env_val
    elseif julia_exe == "auto"
        julia_exe = nothing
    end

    return (
        local_workers=local_workers,
        default_workers=default_workers,
        julia=julia_exe,
        skip_hash_check=skip_hash_check,
        enable_log=enable_log,
        log_dir=log_dir,
        explicit_package=explicit_package,
        hosts=hosts,
        script_path=script_path,
        script_args=script_args,
        collect_root=nothing,
        collect_hosts=nothing,
        collect_overwrite=nothing,
        help=false,
    )
end

function runner_help_text()::String
    """
Usage:
  julia --project=. -m SSHRunner runner [options] [hosts...] script.jl [script_args...]

Collect-only (no script):
  julia --project=. -m SSHRunner runner --collect-missing ROOT HOST [HOST...]
  julia --project=. -m SSHRunner runner --collect-overwrite ROOT HOST [HOST...]
  (aliases: --collect-tree == --collect-missing; --collect-tree-sync == --collect-overwrite)

Options:
  -l, --local N       Number of local worker processes (default: 0)
  -w, --workers N     Default workers for remote hosts without explicit count
  --julia PATH        Julia path for remote hosts (default: auto = detect common paths)
  --skip-hash-check   Skip git hash verification between local and remote hosts
  --no-log            Do not write console output to a log file
  --log-dir PATH      Log output directory (default: script's output dir, or <script_dir>/results)
  --package NAME      `using NAME` on workers (overrides package name from Project.toml)
  --collect-missing ROOT HOST...
                      files under ROOT missing locally only (by relative path)
  --collect-overwrite ROOT HOST...
                      rsync-merge entire tree under ROOT (same-named local files replaced from remote)
  --collect-tree / --collect-tree-sync  aliases for the above flags (older names)
  -h, --help          Show this help

Arguments:
  hosts...        Remote hosts: "host" or "host:workers" (e.g., host1:10)
  script.jl       Julia script to run (required)
  script_args...  Arguments passed to the script

Worker counts:
  - Local: --local N (default: 0, master only)
  - Remote: host:N if specified, else --workers value, else 1

Examples:
  # Local + remote (9 local + 10 + 8 remote = 27 worker processes)
  julia --project=. -m SSHRunner runner --local 9 host1:10 host2:8 myscript.jl

  # Default workers for all remote hosts
  julia --project=. -m SSHRunner runner --local 9 --workers 10 host1 host2 myscript.jl

  # Local only (9 worker processes)
  julia --project=. -m SSHRunner runner --local 9 myscript.jl

  # Remote only (master on local, workers on remotes)
  julia --project=. -m SSHRunner runner host1:10 myscript.jl

  # Pull any file under data/sweep that exists on hosts but not locally (recursive; sweep scripts write here):
  julia --project=. -m SSHRunner runner --collect-missing data/sweep host1 host2

Vendored/submodule form (no install; run the script file directly):
  julia --project=. SSHRunner/src/runner.jl --local 9 myscript.jl

Note:
  This uses Distributed.jl (multi-process parallelism).
  Each worker is a separate Julia process with its own memory.
  For multi-threading within a single process, run your script directly with -t N.

Environment:
  JULIA_DISTRIBUTED_EXE           Default Julia path for remote hosts
  DISTRIBUTED_OUTPUT_DIR          Output dir set by distributed scripts (runner log default + legacy single-tree rsync)
  DISTRIBUTED_COLLECT_DIRS        Colon-separated local abs or repo-relative dirs to rsync after runs (overrides single-tree default)
  DISTRIBUTED_REMOTE_PROJECT_ROOT If workers clone the repo elsewhere: absolute path to repo root **on SSH hosts**
                                  (setup.jl, git hash checks, addprocs dir/--project, collect / sentinel)

Prerequisites:
  - SSH key authentication to remote hosts
  - Same project layout relative to repo root on workers (or set DISTRIBUTED_REMOTE_PROJECT_ROOT)
  - Same git commit on all machines (checked automatically, use --skip-hash-check to override)
"""
end
