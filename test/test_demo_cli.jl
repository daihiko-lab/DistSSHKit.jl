using Test

@testset "bundled demos" begin
    @test isdir(DistSSHKit.demos_dir())
    @test DistSSHKit.demo_script("param_sweep") !== nothing
    @test DistSSHKit.demo_script("coin_flip.jl") !== nothing
    @test DistSSHKit.demo_script("no_such_demo") === nothing
    @test "param_sweep" in DistSSHKit.list_demos()
    @test "coin_flip" in DistSSHKit.list_demos()

    mktempdir() do tmp
        result = DistSSHKit.install_demos(tmp)
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
        result2 = DistSSHKit.install_demos(tmp)
        @test isempty(result2.installed)
        @test length(result2.skipped) == 3 # param_sweep.jl, coin_flip.jl, .gitignore
        @test any(==(abspath(edited_path)), result2.skipped)
        @test read(edited_path, String) == "# edited by user\n"

        # --force overwrites back to the bundled version.
        result3 = DistSSHKit.install_demos(tmp; force=true)
        @test isempty(result3.skipped)
        @test occursin("init_output_dir!", read(edited_path, String))
    end

    # Development checkout: installing into the package root itself would target the
    # bundled demos/ — nothing to copy; use demo list or --dest instead.
    kit_root = abspath(joinpath(@__DIR__, ".."))
    @test_throws ArgumentError DistSSHKit.install_demos(kit_root)

    function _main_quiet(args)
        redirect_stdout(devnull) do
            redirect_stderr(devnull) do
                return DistSSHKit.main(args)
            end
        end
    end
    @test _main_quiet(["demo", "--help"]) == 0
    @test _main_quiet(["demo", "bogus"]) == 1

    mktempdir() do tmp
        out = IOBuffer()
        proc = run(
            pipeline(
                `$(joinpath(Sys.BINDIR, Base.julia_exename())) --project=$(abspath(joinpath(@__DIR__, ".."))) -m DistSSHKit demo install --dest $tmp`,
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
