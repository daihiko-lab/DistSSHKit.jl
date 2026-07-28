using Test

@testset "setup.jl" begin
    isdefined(Main, :parse_setup_args) || include(joinpath(@__DIR__, "..", "src", "setup.jl"))

    # -- julia_version_mismatch_kind ----------------------------------------
    @test julia_version_mismatch_kind(v"1.12.6", v"1.12.6") == :none
    @test julia_version_mismatch_kind(v"1.12.6", v"1.12.9") == :patch
    @test julia_version_mismatch_kind(v"1.12.6", v"1.11.6") == :minor
    @test julia_version_mismatch_kind(v"1.12.6", v"2.0.6") == :minor

    # -- parse_setup_args: --ignore-julia-version ----------------------------
    let r = parse_setup_args(["--check", "host1"])
        @test r.ignore_julia_version == false
    end
    let r = parse_setup_args(["--check", "--ignore-julia-version", "host1"])
        @test r.ignore_julia_version == true
    end

    # -- parse_setup_args: --rsync --------------------------------------------
    let r = parse_setup_args(["--rsync", "host1", "host2"])
        @test r.mode == :rsync_push
        @test r.hosts == ["host1", "host2"]
    end

    # -- rsync_push_to_remotes: cancels without confirmation, no SSH needed --
    # `redirect_stdin`/`redirect_stdout` need real files (IOBuffer has no OS-level fd).
    mktemp() do _stdin_path, stdin_io
        println(stdin_io, "")  # empty answer -> readline() returns "" -> treated as cancel
        flush(stdin_io)
        seekstart(stdin_io)
        mktemp() do stdout_path, stdout_io
            result = Ref{Bool}(true)
            redirect_stdout(stdout_io) do
                redirect_stdin(stdin_io) do
                    result[] = rsync_push_to_remotes(["no-such-host.invalid"], "~/App.jl")
                end
            end
            flush(stdout_io)
            @test result[] == false
            @test occursin("Cancelled.", read(stdout_path, String))
        end
    end
end
