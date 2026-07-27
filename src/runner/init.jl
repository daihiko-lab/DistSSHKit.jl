include(joinpath(@__DIR__, "_common.jl"))
using Pkg

function init_runner_workers!(proj_dir::String, explicit_package, root_disp::String)
    write_both("Initializing workers... ")
    flush(stdout)
    try
        worker_ids = workers()
        responses = Int[]
        failed_workers = Int[]

        _ping_retries = something(tryparse(Int, get(ENV, "DISTRIBUTED_PING_RETRIES", "6")), 6)
        for w in worker_ids
            local r_ok
            r_ok = nothing
            local last_ex
            last_ex = nothing
            for attempt in 1:max(1, _ping_retries)
                try
                    r_ok = remotecall_fetch(() -> myid(), w)
                    break
                catch e
                    last_ex = e
                    attempt < max(1, _ping_retries) && sleep(0.4 * attempt)
                end
            end
            if r_ok !== nothing
                push!(responses, r_ok)
            else
                push!(failed_workers, w)
                @warn "Worker $w not responding" exception=something(last_ex, ErrorException("unknown"))
            end
        end

        if !isempty(failed_workers)
            writeln_both("($(length(failed_workers)) workers failed to respond)")
            for w in failed_workers
                try
                    rmprocs(w)
                catch
                end
            end
        end

        isempty(responses) && error("No workers responding")

        print_ok("✓ ($(length(responses)) workers)")
        writeln_both("")
        write_both("  Loading packages on workers... ")
        flush(stdout)

        @eval @everywhere ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
        @eval @everywhere using Pkg
        @eval @everywhere Pkg.activate($proj_dir; io=devnull)

        pkg_name = explicit_package !== nothing ? explicit_package : project_package_name(proj_dir)
        if pkg_name !== nothing
            pkg_sym = Symbol(pkg_name)
            try
                host_workers = Dict{String, Int}()
                for w in workers()
                    host = remotecall_fetch(() -> gethostname(), w)
                    if !haskey(host_workers, host)
                        host_workers[host] = w
                    end
                end

                precompile_futures = [remotecall(w) do
                    Pkg.precompile(; io=devnull)
                end for (_, w) in host_workers]
                for f in precompile_futures
                    fetch(f)
                end

                @eval @everywhere using $pkg_sym

                for w in workers()
                    remotecall_fetch(() -> true, w)
                end

                print_ok("✓ ($pkg_name loaded)")
                writeln_both("")
            catch e
                writeln_both("(package load skipped: $(sprint(showerror, e)))")
            end
        elseif !isfile(joinpath(proj_dir, "Project.toml"))
            writeln_both("(no Project.toml in $(display_path(proj_dir, root_disp)))")
        else
            writeln_both("(no package name in Project.toml; use --package NAME)")
        end

        write_both("  Verifying workers... ")
        flush(stdout)
        test_results = pmap(_ -> (myid(), 1 + 1), workers())
        working_count = count(r -> r[2] == 2, test_results)
        print_ok("✓ ($working_count workers verified)")
        writeln_both("")

        write_both("  Starting heartbeat monitors... ")
        flush(stdout)
        @eval @everywhere begin
            const HEARTBEAT_STOP = Ref(false)

            function stop_heartbeat_monitor()
                HEARTBEAT_STOP[] = true
            end

            function start_heartbeat_monitor()
                myid() == 1 && return
                @async begin
                    consecutive_failures = 0
                    max_failures = 6
                    while !HEARTBEAT_STOP[]
                        sleep(10)
                        HEARTBEAT_STOP[] && break
                        try
                            remotecall_fetch(() -> true, 1)
                            consecutive_failures = 0
                        catch
                            consecutive_failures += 1
                            if consecutive_failures >= max_failures
                                exit(0)
                            end
                        end
                    end
                end
            end
        end
        @everywhere start_heartbeat_monitor()

        for w in workers()
            remotecall_fetch(() -> (flush(stdout); flush(stderr); true), w)
        end
        print_ok("✓")
        writeln_both("")
    catch e
        print_err("✗")
        writeln_both("")
        @warn "Worker initialization failed" exception=e
        writeln_both("Continuing anyway...")
    end
    writeln_both("")
end
