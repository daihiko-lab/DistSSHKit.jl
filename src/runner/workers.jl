function cleanup_stale_workers!(hosts)
    writeln_both("Cleaning up stale workers...")

    try
        run(pipeline(Cmd(["pkill", "-9", "-f", "julia.*--worker"]), stdout=devnull, stderr=devnull))
    catch
    end
    try
        run(pipeline(Cmd(["pkill", "-9", "-f", "julia.*--bind-to"]), stdout=devnull, stderr=devnull))
    catch
    end
    write_both("  localhost: ")
    print_ok("✓")
    writeln_both("")

    for (host_name, _) in hosts
        try
            cleanup_cmd = """
                pkill -9 -f 'julia.*worker' 2>/dev/null
                pkill -9 -f 'julia.*--bind-to' 2>/dev/null
                true
            """
            cmd = Cmd(["ssh", SSH_OPTS..., host_name, cleanup_cmd])
            run(pipeline(cmd, stdout=devnull, stderr=devnull))
            write_both("  $host_name: ")
            print_ok("✓")
            writeln_both("")
        catch e
            writeln_both("  $host_name: (skipped - $e)")
        end
    end
    writeln_both("")
end

function add_runner_workers!(
    hosts,
    local_workers::Int,
    default_workers,
    julia_exe,
    proj_dir::String,
    script_dir::String,
)::Vector{String}
    writeln_both("Adding workers...")

    successful_hosts = String[]

    if local_workers > 0
        write_both("  localhost ($local_workers workers): ")
        try
            addprocs(local_workers; exeflags=`--project=$proj_dir`, topology=:master_worker)
            print_ok("✓")
            writeln_both("")
        catch e
            print_err("✗ ($e)")
            writeln_both("")
        end
    else
        writeln_both("  localhost: master only (use --local N for local workers)")
    end

    sshflags_cmd = Cmd(collect(String, SSH_OPTS))

    for (host_name, host_workers_spec) in hosts
        host_julia = julia_exe
        if host_julia === nothing
            write_both("  $host_name: detecting Julia... ")
            host_julia = detect_julia_path(host_name)
            if host_julia === nothing
                print_err("✗ (Julia not found)")
                writeln_both("")
                continue
            end
            print_info("found at $host_julia")
            writeln_both("")
            write_both("  ")
        end

        host_workers = something(host_workers_spec, default_workers, 1)

        repo_ra = abspath(expanduser(String(PROJECT_ROOT)))
        remote_dir = remote_path_for_ssh_collect(script_dir, repo_ra)
        remote_proj = remote_path_for_ssh_collect(proj_dir, repo_ra)

        write_both("$host_name ($host_workers workers): ")
        try
            addprocs([(host_name, host_workers)];
                     exename=`$host_julia`,
                     sshflags=sshflags_cmd,
                     dir=remote_dir,
                     tunnel=true,
                     topology=:master_worker,
                     exeflags=`--project=$remote_proj`)
            print_ok("✓")
            writeln_both("")
            push!(successful_hosts, host_name)
        catch e
            print_err("✗")
            writeln_both("")
            if e isa CompositeException
                for (i, ex) in enumerate(e.exceptions)
                    actual_ex = ex isa TaskFailedException ? ex.task.result : ex
                    writeln_both("    Error $i: $(typeof(actual_ex))")
                    msg = sprint(showerror, actual_ex)
                    first_line = first(split(msg, '\n'))
                    writeln_both("    $first_line")
                end
            else
                writeln_both("    $(sprint(showerror, e))")
            end
        end
    end

    writeln_both("")
    writeln_both("Workers: $(nworkers())")
    writeln_both("")

    nworkers() == 0 && error("No workers available. Check SSH connectivity.")

    return successful_hosts
end

function wait_for_worker_connections!()
    _init_delay = tryparse(Float64, get(ENV, "DISTRIBUTED_INIT_DELAY_SEC", "5"))
    if _init_delay !== nothing && _init_delay > 0
        write_both("Waiting for worker connections ($(round(_init_delay, digits=1))s)... ")
        flush(stdout)
        sleep(_init_delay)
        print_ok("✓")
        writeln_both("")
    end
end

function register_worker_cleanup!(successful_hosts::Vector{String})
    cleanup_registered = Ref(false)
    function cleanup_workers()
        cleanup_registered[] && return
        cleanup_registered[] = true

        if nworkers() > 0
            try
                @everywhere stop_heartbeat_monitor()
                sleep(0.5)
            catch
            end
        end

        if nworkers() > 0
            try
                rmprocs(workers(); waitfor=5.0)
            catch
            end
        end

        for host in successful_hosts
            try
                cleanup_cmd = "pkill -9 -f 'julia.*worker' 2>/dev/null; pkill -9 -f 'julia.*--bind-to' 2>/dev/null; true"
                cmd = Cmd(["ssh", SSH_OPTS..., host, cleanup_cmd])
                run(pipeline(cmd, stdout=devnull, stderr=devnull); wait=true)
            catch
            end
        end
    end
    atexit(cleanup_workers)
    return cleanup_workers
end
