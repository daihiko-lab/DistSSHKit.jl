using .DistSSHKit: get_local_git_hash, get_remote_git_hash, get_remote_total_gb,
    print_err, print_ok, print_warn, write_both, writeln_both

# Runner-only preflight checks (git parity, memory capacity).

const WORKER_MEMORY_GB_FALLBACK = 1.5

function estimate_worker_memory_gb()
    try
        rss_bytes = Sys.maxrss()
        if rss_bytes > 0
            return max(rss_bytes / 1024^3 * 1.2, 0.5)
        end
    catch
    end
    return WORKER_MEMORY_GB_FALLBACK
end

function estimate_available_gb()
    total = Sys.total_memory() / 1024^3
    free = Sys.free_memory() / 1024^3
    return (total, max(free, total * 0.5))
end

function check_memory_capacity(local_workers::Int, hosts::Vector{Tuple{String,Union{Int,Nothing}}}, default_workers::Union{Int,Nothing})::Bool
    per_worker = estimate_worker_memory_gb()
    r(x) = round(x, digits=1)
    writeln_both("Checking memory capacity...")
    writeln_both("  Per-worker estimate: $(round(per_worker, digits=2))GB")
    warnings = String[]

    function check_host(label::String, n_workers::Int, total_gb)
        if total_gb === nothing
            writeln_both("  $label: (memory check failed)")
            return
        end
        avail = total_gb * 0.7
        estimated = n_workers * per_worker
        max_w = max(1, floor(Int, avail / per_worker))
        if estimated > avail
            push!(warnings, "  $label: $(n_workers) × $(r(per_worker))GB = $(r(estimated))GB > $(r(avail))GB (70% of $(r(total_gb))GB)")
            write_both("  $label: $(r(total_gb))GB, $(n_workers) workers → ")
            print_warn("⚠ (max ~$(max_w))")
            writeln_both("")
        else
            write_both("  $label: $(r(total_gb))GB, $(n_workers) workers → ")
            print_ok("✓")
            writeln_both("")
        end
    end

    if local_workers > 0
        total, _ = estimate_available_gb()
        check_host("localhost", local_workers + 1, total)
    end

    host_totals = Dict{String,Int}()
    for (host_name, host_workers_spec) in hosts
        n = something(host_workers_spec, default_workers, 1)
        host_totals[host_name] = get(host_totals, host_name, 0) + n
    end

    for (host_name, host_workers) in host_totals
        check_host(host_name, host_workers, get_remote_total_gb(host_name))
    end
    writeln_both("")

    if !isempty(warnings)
        print_warn("WARNING: ", bold=true)
        writeln_both("Memory pressure detected!")
        writeln_both("")
        for w in warnings
            print_warn(w * "\n")
        end
        writeln_both("")
        writeln_both("Consider reducing worker count.")
        writeln_both("")
        write_both("Continue anyway? [y/N]: ")
        response = readline()
        if lowercase(strip(response)) != "y"
            writeln_both("Aborted.")
            return false
        end
        writeln_both("")
    end
    return true
end

function check_git_hashes(hosts::Vector{String}, proj_dir::String)
    local_hash = get_local_git_hash(proj_dir)
    if local_hash === nothing
        write_both("  ")
        print_warn("⚠ Could not get local git hash (not a git repo?)")
        writeln_both("")
        return true, String[]
    end

    # Prefer DISTRIBUTED_REMOTE_PROJECT_ROOT when set; otherwise keep legacy
    # identical-absolute-path checks (setup.jl defaults to ~/Parent/Name separately).
    env_remote = strip(get(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT", ""))
    remote_root = isempty(env_remote) ? String(proj_dir) : env_remote

    writeln_both("  Local: $(local_hash[1:8])...")
    if !isempty(env_remote)
        writeln_both("  Remote project root: $remote_root")
    end

    mismatches = String[]
    for host in hosts
        remote_hash = get_remote_git_hash(host, remote_root)
        if remote_hash === nothing
            write_both("  $host: ")
            print_warn("⚠ Could not get git hash")
            writeln_both("")
        elseif remote_hash != local_hash
            write_both("  $host: ")
            print_err("✗ $(remote_hash[1:8])... (MISMATCH)")
            writeln_both("")
            push!(mismatches, host)
        else
            write_both("  $host: ")
            print_ok("✓ $(remote_hash[1:8])...")
            writeln_both("")
        end
    end

    return isempty(mismatches), mismatches
end
