using Test

@testset "bundled demos" begin
    @test isdir(SSHRunner.demos_dir())
    @test SSHRunner.demo_script("param_sweep") !== nothing
    @test SSHRunner.demo_script("coin_flip.jl") !== nothing
    @test SSHRunner.demo_script("no_such_demo") === nothing
    @test "param_sweep" in SSHRunner.list_demos()
    @test "coin_flip" in SSHRunner.list_demos()

    mktempdir() do tmp
        result = SSHRunner.install_demos(tmp)
        @test length(result.installed) == 2
        @test isempty(result.skipped)
        @test all(isfile, result.installed)
        @test isfile(joinpath(tmp, "demos", "param_sweep.jl"))
        @test isfile(joinpath(tmp, "demos", "coin_flip.jl"))
        @test isfile(joinpath(tmp, "demos", ".gitignore"))
        @test occursin("init_output_dir!", read(joinpath(tmp, "demos", "param_sweep.jl"), String))

        # Re-installing without --force leaves existing (possibly user-edited) files alone.
        edited_path = joinpath(tmp, "demos", "param_sweep.jl")
        write(edited_path, "# edited by user\n")
        result2 = SSHRunner.install_demos(tmp)
        @test isempty(result2.installed)
        @test length(result2.skipped) == 3 # param_sweep.jl, coin_flip.jl, .gitignore
        @test any(==(abspath(edited_path)), result2.skipped)
        @test read(edited_path, String) == "# edited by user\n"

        # --force overwrites back to the bundled version.
        result3 = SSHRunner.install_demos(tmp; force=true)
        @test isempty(result3.skipped)
        @test occursin("init_output_dir!", read(edited_path, String))
    end

    # Development checkout: installing into the package root itself would target the
    # bundled demos/ — nothing to copy; use demo list or --dest instead.
    kit_root = abspath(joinpath(@__DIR__, ".."))
    @test_throws ArgumentError SSHRunner.install_demos(kit_root)

    function _main_quiet(args)
        redirect_stdout(devnull) do
            redirect_stderr(devnull) do
                return SSHRunner.main(args)
            end
        end
    end
    @test _main_quiet(["demo", "--help"]) == 0
    @test _main_quiet(["demo", "bogus"]) == 1

    mktempdir() do tmp
        out = IOBuffer()
        proc = run(
            pipeline(
                `$(joinpath(Sys.BINDIR, Base.julia_exename())) --project=$(abspath(joinpath(@__DIR__, ".."))) -m SSHRunner demo install --dest $tmp`,
                stdout=out,
                stderr=out,
            ),
            wait=true,
        )
        @test proc.exitcode == 0
        text = String(take!(out))
        @test occursin("wrote ", text)
        @test isfile(joinpath(tmp, "demos", "coin_flip.jl"))
    end
end
