using Test

@testset "runner args" begin
    _runner_dir = joinpath(@__DIR__, "..", "src", "runner")
    isdefined(Main, :parse_runner_args) || include(joinpath(_runner_dir, "args.jl"))
    isdefined(Main, :check_memory_capacity) || include(joinpath(_runner_dir, "checks.jl"))

    @test_throws ArgumentError parse_runner_args(["--collect", "h"])
    @test_throws ArgumentError parse_runner_args(["--collect-sync", "data/sweep", "host"])

    let r = parse_runner_args(["--collect-missing", "data/sweep", "host-a", "host-b"])
        @test r.collect_root == abspath("data/sweep")
        @test r.collect_hosts == ["host-a", "host-b"]
        @test r.collect_overwrite == false
        @test r.script_path === nothing
    end

    let r = parse_runner_args(["--collect-tree", "data/sweep", "host-a", "host-b"])
        @test r.collect_root == abspath("data/sweep")
        @test r.collect_hosts == ["host-a", "host-b"]
        @test r.collect_overwrite == false
    end

    let r = parse_runner_args(["--collect-overwrite", "data/sweep", "host-a"])
        @test r.collect_root == abspath("data/sweep")
        @test r.collect_hosts == ["host-a"]
        @test r.collect_overwrite == true
    end

    let r = parse_runner_args(["--collect-tree-sync", "data/sweep", "host-a"])
        @test r.collect_root == abspath("data/sweep")
        @test r.collect_hosts == ["host-a"]
        @test r.collect_overwrite == true
    end

    @test_throws ArgumentError parse_runner_args(["--collect-missing", "data/sweep"])

    @test estimate_worker_memory_gb() > 0
    let (total, avail) = estimate_available_gb()
        @test total > 0
        @test avail > 0
        @test avail <= total || avail == total * 0.5
    end

    @test _parse_host_workers_spec("host-a") == ("host-a", nothing)
    @test _parse_host_workers_spec("host-a:10") == ("host-a", 10)

    withenv("JULIA_DISTRIBUTED_EXE" => nothing) do
        let r = parse_runner_args(["--help"])
            @test r.help == true
        end
        let r = parse_runner_args(["-h"])
            @test r.help == true
        end
        let r = parse_runner_args(["--local", "4", "myscript.jl", "a", "b"])
            @test r.local_workers == 4
            @test r.script_path == "myscript.jl"
            @test r.script_args == ["a", "b"]
            @test r.help == false
        end
        let r = parse_runner_args(["--workers", "3", "host1", "host2:5", "s.jl"])
            @test r.default_workers == 3
            @test r.hosts == [("host1", nothing), ("host2", 5)]
            @test r.script_path == "s.jl"
        end
        let r = parse_runner_args(["--julia", "/usr/bin/julia", "s.jl"])
            @test r.julia == "/usr/bin/julia"
        end
        let r = parse_runner_args(["--julia", "auto", "s.jl"])
            @test r.julia === nothing
        end
        let r = parse_runner_args(["--skip-hash-check", "s.jl"])
            @test r.skip_hash_check == true
        end
        let r = parse_runner_args(["--no-hash-check", "s.jl"])
            @test r.skip_hash_check == true
        end
        let r = parse_runner_args(["--no-log", "s.jl"])
            @test r.enable_log == false
        end
        let r = parse_runner_args(["--log-dir", "/tmp/logs", "s.jl"])
            @test r.log_dir == "/tmp/logs"
        end
        let r = parse_runner_args(["--package", "MyPkg", "s.jl"])
            @test r.explicit_package == "MyPkg"
        end
        let r = parse_runner_args(["--package", "  ", "s.jl"])
            @test r.explicit_package === nothing
        end
        let r = parse_runner_args(String[])
            @test r.script_path === nothing
            @test r.help == false
        end
    end
    withenv("JULIA_DISTRIBUTED_EXE" => "/opt/custom/julia") do
        let r = parse_runner_args(["s.jl"])
            @test r.julia == "/opt/custom/julia"
        end
    end

    let txt = runner_help_text()
        @test occursin("Usage:", txt)
        @test occursin("--collect-missing", txt)
        @test occursin("JULIA_DISTRIBUTED_EXE", txt)
    end

    function _init_git_repo!(d::String)
        run(Cmd(["git", "-C", d, "init", "-q"]))
        run(Cmd(["git", "-C", d, "config", "user.email", "test@example.com"]))
        run(Cmd(["git", "-C", d, "config", "user.name", "Test"]))
        write(joinpath(d, "f.txt"), "hi")
        run(Cmd(["git", "-C", d, "add", "f.txt"]))
        run(Cmd(["git", "-C", d, "commit", "-q", "-m", "init"]))
    end

    function _capture_check_git_hashes(hosts, d)
        result = Ref{Any}(nothing)
        out = mktemp() do _, io
            redirect_stdout(io) do
                result[] = check_git_hashes(hosts, d)
            end
            seekstart(io)
            read(io, String)
        end
        ok, mismatches = result[]
        return ok, mismatches, out
    end

    mktempdir() do tmp
        d = abspath(string(tmp))
        ok, mismatches, out = _capture_check_git_hashes(String[], d)
        @test ok == true
        @test mismatches == String[]
        @test occursin("Could not get local git hash", out)
    end

    mktempdir() do tmp
        d = abspath(string(tmp))
        _init_git_repo!(d)
        ok, mismatches, out = _capture_check_git_hashes(String[], d)
        @test ok == true
        @test mismatches == String[]
        @test occursin("Local:", out)
        @test !occursin("Could not get local git hash", out)
    end
end
