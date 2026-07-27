function place_runner_sentinels!(successful_hosts::Vector{String}, script_dir::String, skip_collect::Bool)::String
    skip_collect || isempty(successful_hosts) && return ""
    sentinel_name = ".runner_sentinel_$(getpid())_$(Dates.format(now(), "yyyymmddTHHMMSS"))"
    repo_ra = abspath(String(PROJECT_ROOT))
    collect_roots_sentinel = distributed_collect_root_dirs(script_dir, repo_ra)
    for local_rd in collect_roots_sentinel
        _early_local = abspath(String(local_rd))
        for host in unique(successful_hosts)
            try
                remote_early = remote_path_for_ssh_collect(_early_local, repo_ra)
                run(pipeline(Cmd(["ssh", SSH_OPTS..., host, "mkdir", "-p", remote_early]),
                    stdout=devnull, stderr=devnull))
                run(pipeline(Cmd(["ssh", SSH_OPTS..., host, "touch", joinpath(remote_early, sentinel_name)]),
                    stdout=devnull, stderr=devnull))
            catch; end
        end
    end
    return sentinel_name
end

function run_driver_script!(enable_log::Bool, cleanup_workers)
    writeln_both("Running script...")
    writeln_both("")
    run_script = () -> begin
        Base.invokelatest() do
            if isdefined(Main, :main)
                main_fn = getfield(Main, :main)
                if main_fn isa Function
                    Base.invokelatest(Base.inferencebarrier(main_fn))
                end
            end
        end
    end
    try
        if enable_log && LOG_FILE_HANDLE[] !== nothing
            orig_stdout = stdout
            log_io = LOG_FILE_HANDLE[]
            linebuf = UInt8[]
            rd, wr = redirect_stdout()
            reader = @async begin
                try
                    while true
                        data = readavailable(rd)
                        if !isempty(data)
                            write(orig_stdout, data)
                            for b in data
                                if b == 0x0d
                                    empty!(linebuf)
                                elseif b == 0x0a
                                    write(log_io, linebuf)
                                    write(log_io, b)
                                    flush(log_io)
                                    empty!(linebuf)
                                else
                                    push!(linebuf, b)
                                end
                            end
                        end
                        # NOTE: no `yield()` here on an empty read — `readavailable` already
                        # blocks until data or close, so spin-yielding instead of letting it
                        # block starves libuv's notice of `wr` closing (observed ~30s stalls).
                        isempty(data) && (eof(rd) || !isopen(wr)) && break
                    end
                    if !isempty(linebuf)
                        write(log_io, linebuf)
                        flush(log_io)
                    end
                catch e
                    isa(e, Base.IOError) || rethrow()
                end
            end
            try
                run_script()
            finally
                flush(stdout)
                close(wr)
                # `rd` normally reaches EOF once `wr` closes, but local worker processes
                # (spawned via `addprocs`) inherit our stdout fd and keep the underlying
                # pipe open until they exit, so EOF may never arrive here. All real script
                # output is already flushed to `rd` by this point (readavailable drains it
                # as it's written), so a short grace period is enough before we force-close.
                wait_ok = @async wait(reader)
                for _ in 1:20
                    istaskdone(wait_ok) && break
                    sleep(0.05)
                end
                if !istaskdone(wait_ok)
                    close(rd)
                    wait(reader)
                end
                redirect_stdout(orig_stdout)
            end
        else
            run_script()
        end
    catch e
        if e isa InterruptException
            writeln_both("\nInterrupted. Cleaning up workers...")
            cleanup_workers()
            exit(130)
        end
        rethrow()
    end
end

function collect_runner_results!(
    successful_hosts::Vector{String},
    script_dir::String,
    sentinel_name::String,
    skip_collect::Bool,
    root_disp::String,
)
    results_dir = get(ENV, "DISTRIBUTED_OUTPUT_DIR", nothing)
    if results_dir === nothing
        results_dir = normpath(joinpath(script_dir, "..", "results"))
    end
    results_dir = abspath(results_dir)

    if isempty(successful_hosts)
        writeln_both("")
        writeln_both("Results: $(display_path(results_dir, root_disp))")
        return
    end

    writeln_both("")
    if skip_collect
        writeln_both("Results saved locally (no remote collection needed).")
        writeln_both("Results: $(display_path(results_dir, root_disp))")
        return
    end

    collect_roots = distributed_collect_root_dirs(script_dir, abspath(String(PROJECT_ROOT)))
    for local_rd in collect_roots
        mkpath(local_rd)
    end
    writeln_both("Collecting results from remote hosts...")
    repo_ra = abspath(String(PROJECT_ROOT))
    for host in unique(successful_hosts)
        write_both("  $host: ")
        total_for_host = 0
        host_err = nothing
        try
            ssh_cmd = "ssh " * join(SSH_OPTS, " ")
            for local_rd in collect_roots
                local_abs = abspath(String(local_rd))
                remote_rd_collect = remote_path_for_ssh_collect(local_abs, repo_ra)
                remote_sentinel = joinpath(remote_rd_collect, sentinel_name)
                try
                    remote_find_raw = try
                        strip(
                            read(
                                pipeline(
                                    Cmd([
                                        "ssh",
                                        SSH_OPTS...,
                                        host,
                                        "find",
                                        remote_rd_collect,
                                        "-type",
                                        "f",
                                        "-newer",
                                        remote_sentinel,
                                        "!",
                                        "-name",
                                        sentinel_name,
                                        "-print",
                                    ]);
                                    stderr=devnull,
                                ),
                                String,
                            ),
                        )
                    catch
                        ""
                    end
                    rroot = String(rstrip(String(remote_rd_collect), '/'))
                    rel_lines = String[]
                    for line in split(remote_find_raw, '\n')
                        lp = strip(String(line))
                        isempty(lp) && continue
                        rel = if startswith(lp, rroot * "/")
                            lp[(length(rroot) + 2):end]
                        else
                            continue
                        end
                        isempty(rel) && continue
                        push!(rel_lines, rel)
                    end
                    file_list = join(unique(rel_lines), '\n')

                    if !isempty(file_list)
                        remote_uri = string(host, ":", remote_rd_collect, "/")
                        rsync_part = Cmd(String[
                            "rsync",
                            "-az",
                            "-e",
                            ssh_cmd,
                            "--files-from=-",
                            remote_uri,
                            local_abs * "/",
                        ])
                        buf = IOBuffer()
                        print(buf, strip(file_list))
                        write(buf, '\n')
                        seekstart(buf)
                        run(pipeline(rsync_part; stdin=buf, stderr=stderr))
                        total_for_host +=
                            count(!isempty(strip(l)) for l in split(file_list, '\n'))
                    end
                catch e
                    host_err === nothing && (host_err = e)
                finally
                    try
                        run(pipeline(Cmd(["ssh", SSH_OPTS..., host, "rm", "-f", remote_sentinel]),
                                     stdout=devnull, stderr=devnull))
                    catch; end
                end
            end
            if host_err !== nothing
                print_err("✗ ($host_err)")
            elseif total_for_host == 0
                print_warn("(nothing to collect)")
            else
                print_ok("✓ ($total_for_host file$(total_for_host == 1 ? "" : "s"))")
            end
            writeln_both("")
        catch e
            print_err("✗ ($e)")
            writeln_both("")
        end
    end
    coll_disp = join(
        (display_path(String(p), root_disp) for p in collect_roots),
        ", ",
    )
    writeln_both("Results collected to: $coll_disp")
end
