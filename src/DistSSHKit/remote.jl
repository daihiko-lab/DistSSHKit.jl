# =============================================================================
# SSH Configuration
# =============================================================================

"""Build SSH options for non-interactive connections."""
function build_ssh_opts()
    custom = strip(get(ENV, "DISTRIBUTED_SSH_OPTS", ""))
    if isempty(custom)
        return [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=60",
            "-o", "ServerAliveCountMax=10",
            "-o", "TCPKeepAlive=yes",
        ]
    end
    return split(custom)
end

const SSH_OPTS = build_ssh_opts()

"""Parse `julia --version` output (e.g. `"julia version 1.12.6"`) into a `VersionNumber`.
Returns `nothing` if the text doesn't match the expected pattern."""
function parse_julia_version(version_output::AbstractString)::Union{Nothing,VersionNumber}
    m = match(r"julia version (\d+\.\d+\.\d+)", String(version_output))
    m === nothing && return nothing
    cap = m.captures[1]
    cap isa AbstractString || return nothing
    try
        return VersionNumber(String(cap))
    catch
        return nothing
    end
end

"""Get the Julia version on a remote host by running `julia_path --version` over SSH.
Returns `nothing` on any failure (SSH, missing binary, unparseable output)."""
function get_remote_julia_version(host::String, julia_path::AbstractString)::Union{Nothing,VersionNumber}
    try
        result = read(pipeline(Cmd(["ssh", SSH_OPTS..., host, String(julia_path), "--version"]); stderr=devnull), String)
        return parse_julia_version(result)
    catch
        return nothing
    end
end

"""Detect Julia path on remote host via SSH."""
function detect_julia_path(host::String)
    common_paths = [
        "/opt/homebrew/bin/julia",
        "/usr/local/bin/julia",
        raw"$HOME/.juliaup/bin/julia",
        "/usr/bin/julia",
    ]
    for path in common_paths
        try
            result = read(Cmd(["ssh", SSH_OPTS..., host, "test -x $path && echo $path"]), String)
            found = strip(result)
            isempty(found) || return String(found)
        catch
            continue
        end
    end
    try
        result = read(Cmd(["ssh", SSH_OPTS..., host, "which julia"]), String)
        p = strip(result)
        return isempty(p) ? nothing : String(p)
    catch
        return nothing
    end
end

# =============================================================================
# Git Utilities
# =============================================================================

"""Get local git commit hash (`short=nothing` → full hash, else `git rev-parse --short`)."""
function get_local_git_hash(proj_dir::AbstractString; short::Union{Nothing,Int}=nothing)::Union{Nothing,String}
    resolved = abspath(expanduser(String(proj_dir)))
    try
        cmd = if short === nothing
            Cmd(["git", "-C", resolved, "rev-parse", "HEAD"])
        else
            Cmd(["git", "-C", resolved, "rev-parse", "--short=$(short)", "HEAD"])
        end
        s = strip(read(pipeline(cmd; stderr=devnull), String))
        return isempty(s) ? nothing : s
    catch
        return nothing
    end
end

"""Whether the local git working tree at `proj_dir` is clean (no uncommitted changes).
Returns `true` if clean, if `proj_dir` is not a git repo, or if `git` itself fails —
this check exists to warn, not to block, so failures to determine status don't count
as "dirty"."""
function local_git_clean(proj_dir::AbstractString)::Bool
    resolved = abspath(expanduser(String(proj_dir)))
    try
        result = read(pipeline(Cmd(["git", "-C", resolved, "status", "--porcelain"]); stderr=devnull), String)
        return isempty(strip(result))
    catch
        return true
    end
end

"""
Get remote git commit hash via SSH.

`remote_repo_dir` starting with `~` uses `cd DIR && git rev-parse …` (shell expands `~`);
otherwise uses `git -C DIR rev-parse …` (absolute path on the remote, same layout as local).
"""
function get_remote_git_hash(host::String, remote_repo_dir::AbstractString; short::Union{Nothing,Int}=nothing)::Union{Nothing,String}
    try
        dir = strip(String(remote_repo_dir))
        rev = short === nothing ? "HEAD" : "--short=$(short) HEAD"
        inner = if startswith(dir, "~")
            "cd $(dir) && git rev-parse $(rev)"
        else
            "git -C $(dir) rev-parse $(rev)"
        end
        s = strip(read(pipeline(Cmd(["ssh", SSH_OPTS..., host, inner]); stderr=devnull), String))
        return isempty(s) ? nothing : s
    catch
        return nothing
    end
end

# =============================================================================
# Remote Resource Detection
# =============================================================================

"""Get total memory (GB) for a remote host via SSH."""
function get_remote_total_gb(host::String)
    try
        s = strip(read(pipeline(Cmd(["ssh", SSH_OPTS..., host,
            "sysctl -n hw.memsize 2>/dev/null || awk '/MemTotal/{print \$2*1024}' /proc/meminfo 2>/dev/null"]),
            stderr=devnull), String))
        isempty(s) && return nothing
        return parse(Float64, s) / 1024^3
    catch end
    return nothing
end

"""Get CPU core count for a remote host via SSH."""
function get_remote_nproc(host::String)
    try
        s = strip(read(pipeline(Cmd(["ssh", SSH_OPTS..., host,
            "sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null"]), stderr=devnull), String))
        isempty(s) && return nothing
        return parse(Int, s)
    catch end
    return nothing
end

"""Get total memory (GB) and CPU cores for localhost."""
function get_local_resources()
    total_gb = Sys.total_memory() / 1024^3
    nproc = try
        s = strip(read(pipeline(`sysctl -n hw.ncpu`, stderr=devnull), String))
        isempty(s) ? Sys.CPU_THREADS : parse(Int, s)
    catch
        Sys.CPU_THREADS
    end
    return (total_gb=total_gb, nproc=nproc)
end

# =============================================================================
# Remote Path Resolution & Result Collection
# =============================================================================

"""
List all files under `remote_root` on `host` recursively via SSH `find`, returning
`(remote_abs_path, relative_path)` pairs (relative to `remote_root`).
"""
function collect_tree_remote_files_ssh(host::AbstractString, remote_root::AbstractString)::Vector{Tuple{String,String}}
    hp  = String(host)
    rr  = String(remote_root)
    out = try
        read(
            pipeline(
                Cmd(["ssh", SSH_OPTS..., hp, "find", rr, "-type", "f", "-print"]);
                stderr=devnull,
            ),
            String,
        )
    catch
        return Tuple{String,String}[]
    end
    sep = endswith(rr, "/") ? rr : (rr * "/")
    pairs = Tuple{String,String}[]
    for line in split(out, '\n')
        p = String(strip(line))
        isempty(p) && continue
        rel = startswith(p, sep) ? p[length(sep)+1:end] : String(relpath(p, rr))
        isempty(rel) && continue
        push!(pairs, (p, rel))
    end
    return pairs
end

"""Map remote absolute path under `remote_repo` to the same repo-relative path under `local_repo`."""
function local_dir_from_remote_mirror(
    remote_abs::AbstractString,
    remote_repo::AbstractString,
    local_repo::AbstractString,
)::String
    ra = String(abspath(remote_abs))
    rr = String(abspath(remote_repo))
    lr = String(abspath(local_repo))
    rel = String(relpath(ra, rr))
    startswith(rel, "..") &&
        throw(ArgumentError("remote path $(repr(ra)) is not under remote repo $(repr(rr))"))
    return String(abspath(joinpath(lr, rel)))
end

"""
Default remote layout used by `setup.jl` when paths are not overridden:
`~/basename(parent)/basename(local_project_root)` (tilde for remote-shell expansion).
"""
function default_remote_project_path(local_project_root::AbstractString)::String
    root = String(abspath(expanduser(String(local_project_root))))
    return joinpath("~", basename(dirname(root)), basename(root))
end

"""
Resolve the repository root path **on SSH worker hosts** for setup / git checks.

Priority:
1. `cli_override` if non-empty (e.g. `setup.jl --remote-path`)
2. `ENV["DISTRIBUTED_REMOTE_PROJECT_ROOT"]` if set (prefer an absolute path on the remote;
   `~` is OK for setup SSH shell commands, but runner collect remapping expands `~` locally)
3. `default_remote_project_path(local_project_root)`

Does not force `abspath` on tilde paths so remote shells can expand `~` per host.
"""
function resolve_remote_project_root(
    local_project_root::AbstractString;
    cli_override::Union{Nothing,AbstractString}=nothing,
)::String
    if cli_override !== nothing
        s = strip(String(cli_override))
        !isempty(s) && return s
    end
    env = strip(get(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT", ""))
    !isempty(env) && return env
    return default_remote_project_path(local_project_root)
end

"""Convert `https://github.com/...` clone URLs to SSH; leave other URLs unchanged."""
function normalize_git_clone_url(url::AbstractString)::String
    origin_url = strip(String(url))
    m = match(r"https://github\.com/(.+)", origin_url)
    if m !== nothing
        cap = m.captures[1]
        return cap isa AbstractString ? ("git@github.com:" * String(cap)) : origin_url
    end
    return origin_url
end

"""Read `origin` from `proj_dir` and return a clone URL (HTTPS GitHub → SSH). `nothing` on failure."""
function clone_url_from_local_origin(proj_dir::AbstractString)::Union{Nothing,String}
    resolved = String(abspath(expanduser(String(proj_dir))))
    try
        origin_url = strip(read(pipeline(Cmd(["git", "-C", resolved, "remote", "get-url", "origin"]);
                                          stderr=devnull), String))
        isempty(origin_url) && return nothing
        return normalize_git_clone_url(origin_url)
    catch
        return nothing
    end
end

"""
Absolute path to use on SSH worker hosts for `find` / rsync source / sentinel.

When `DISTRIBUTED_REMOTE_PROJECT_ROOT` is unset, returns `local_abs_dir` (legacy: identical paths everywhere).

When set, `local_application_repo_root` must prefix `local_abs_dir`; the suffix is appended under the remote root.
Paths must lie under the application repo root on this machine (otherwise falls back to `local_abs_dir`).

Note: `expanduser` runs on this machine. Set `DISTRIBUTED_REMOTE_PROJECT_ROOT` to an **absolute**
path on the remote (not `~/...`) when using collect / `addprocs` remapping.
"""
function remote_path_for_ssh_collect(
    local_abs_dir::AbstractString,
    local_application_repo_root::AbstractString,
)::String
    ld = String(abspath(expanduser(String(local_abs_dir))))
    root = String(abspath(expanduser(String(local_application_repo_root))))
    alt = strip(get(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT", ""))
    if isempty(alt)
        return ld
    end
    rroot = String(abspath(expanduser(alt)))
    if ld == root
        return rroot
    end
    rootpfx = endswith(root, '/') ? root : root * '/'
    if startswith(ld, rootpfx)
        rel = String(relpath(ld, root))
        isempty(rel) && return rroot
        rel == "." && return rroot
        return String(abspath(joinpath(rroot, rel)))
    end
    return ld
end

"""
Local absolute directories used for per-run sentinel placement and post-run rsync from SSH workers.

If `ENV["DISTRIBUTED_COLLECT_DIRS"]` is non-empty: colon-separated list (same convention as POSIX `PATH`).
Each token is `abspath(expanduser(token))` when absolute, otherwise `abspath(joinpath(project_root, token))`.
Empty tokens are skipped; duplicates removed (first occurrence order preserved).

If unset or blank after trimming: a single root from `DISTRIBUTED_OUTPUT_DIR`, or `joinpath(script_dir, "..", "results")` when that env is unset.

Scripts should set `DISTRIBUTED_COLLECT_DIRS` to every tree that may receive new files on workers during the run
(e.g. sweep output plus figures). Logs may stay under `DISTRIBUTED_OUTPUT_DIR` only; omit that path here if logs
should not be rsync'd.
"""
function distributed_collect_root_dirs(
    script_dir::AbstractString,
    project_root::AbstractString,
)::Vector{String}
    spec = String(strip(get(ENV, "DISTRIBUTED_COLLECT_DIRS", "")))
    repo = String(abspath(expanduser(String(project_root))))
    if !isempty(spec)
        out = String[]
        for chunk in split(spec, ':')
            p = String(strip(String(chunk)))
            isempty(p) && continue
            pe = String(expanduser(p))
            ap = String(abspath(isabspath(pe) ? pe : joinpath(repo, pe)))
            push!(out, ap)
        end
        seen = Set{String}()
        uniq = String[]
        for p in out
            p in seen && continue
            push!(seen, p)
            push!(uniq, p)
        end
        if !isempty(uniq)
            return uniq
        end
    end
    rd = get(ENV, "DISTRIBUTED_OUTPUT_DIR", nothing)
    rd = rd === nothing ? normpath(joinpath(String(script_dir), "..", "results")) : String(rd)
    return String[String(abspath(expanduser(rd)))]
end
