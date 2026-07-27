include(joinpath(@__DIR__, "_common.jl"))

"""
Recursively pull files under `local_root` from each host.

- `merge=false`: skip relative paths that already exist locally.
- `merge=true`:  rsync the whole tree (overwrites same-named files).

Uses `DISTRIBUTED_REMOTE_PROJECT_ROOT` (via `remote_path_for_ssh_collect`) to map the local root to the correct path on each host.
"""
function runner_collect_tree(local_root::AbstractString, host_names::Vector{String}; merge::Bool=false)
    root_disp    = abspath(expanduser(String(PROJECT_ROOT)))
    repo_root    = abspath(expanduser(String(PROJECT_ROOT)))
    local_root   = String(abspath(expanduser(String(local_root))))
    ssh_cmd_str  = "ssh " * join(SSH_OPTS, " ")

    println("============================================================")
    println(merge ? "SSHRunner collect-overwrite" : "SSHRunner collect-missing")
    println("============================================================")
    println("local root : ", display_path(local_root, root_disp))
    println("mode       : ", merge ? "full sync (same-named files updated when remote differs)" :
                                     "missing paths only (existing local files left unchanged)")
    println("hosts      : ", join(host_names, ", "))
    println("")

    remote_root = remote_path_for_ssh_collect(local_root, repo_root)
    if remote_root != local_root
        println("remote root: ", remote_root)
        println("")
    end

    ok = true
    for host in host_names
        print("  ", host, ": ")
        flush(stdout)
        try
            if !success(pipeline(
                    Cmd(["ssh", SSH_OPTS..., host, "test", "-d", remote_root]);
                    stderr=devnull, stdout=devnull,
                ))
                println("(skip: no directory on host at ", remote_root, ")")
                println("      hint: export DISTRIBUTED_REMOTE_PROJECT_ROOT=<repo root on SSH host>")
                continue
            end

            remote_files = collect_tree_remote_files_ssh(host, remote_root)
            if isempty(remote_files)
                println("(remote root empty or no files found)")
                continue
            end

            if merge
                # No `--mkpath`: macOS ships BSD rsync without that flag (GNU rsync 3.2.3+).
                rsync_cmd = Cmd(String[
                    "rsync", "-az",
                    "-e", ssh_cmd_str,
                    string(host, ":", remote_root, "/"),
                    local_root * "/",
                ])
                run(pipeline(rsync_cmd; stderr=stderr))
                println("✓ (synced ", length(remote_files), " remote file",
                        length(remote_files) == 1 ? "" : "s", ")")
            else
                need = String[rel for (_, rel) in remote_files
                              if !isfile(joinpath(local_root, rel))]
                if isempty(need)
                    println("(nothing new — all remote files exist locally; use --collect-overwrite to replace)")
                    continue
                end
                sort!(need)
                # `--files-from` does not create parents on BSD rsync; pre-create (GNU rsync `--mkpath` unavailable).
                for rel in need
                    d = dirname(joinpath(local_root, rel))
                    !isempty(d) && mkpath(d)
                end
                rsync_cmd = Cmd(String[
                    "rsync", "-az",
                    "-e", ssh_cmd_str,
                    "--files-from=-",
                    string(host, ":", remote_root, "/"),
                    local_root * "/",
                ])
                buf = IOBuffer()
                foreach(p -> println(buf, p), need)
                seekstart(buf)
                run(pipeline(rsync_cmd; stdin=buf, stderr=stderr))
                n = length(need)
                println("✓ ($n file", n == 1 ? "" : "s", ")")
            end
        catch e
            ok = false
            println("✗ ", sprint(showerror, e))
        end
    end
    println("")
    ok || println("(some hosts failed; exit 1)")
    return ok
end
