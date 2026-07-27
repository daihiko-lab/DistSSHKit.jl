using Test

@testset "runner --local" begin
    kit_root = abspath(joinpath(@__DIR__, ".."))
    runner = joinpath(kit_root, "src", "runner.jl")
    fixture = abspath(joinpath(@__DIR__, "fixtures", "runner_local_smoke.jl"))
    @test isfile(runner)
    @test isfile(fixture)

    julia = joinpath(Sys.BINDIR, Base.julia_exename())

    mktempdir() do tmp
        proj = abspath(string(tmp))
        write(joinpath(proj, "Project.toml"), "name = \"SmokeApp\"\n")
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)

        cmd = setenv(
            `$julia --project=$proj $runner --local 2 --no-log $script`,
            merge(filter(!isempty, ENV), Dict(
                "DISTRIBUTED_INIT_DELAY_SEC" => "0",
                "DISTRIBUTED_PROJECT_ROOT" => proj,
            )),
        )
        out = IOBuffer()
        proc = run(pipeline(cmd, stdout=out, stderr=out), wait=true)
        combined = String(take!(out))
        @test proc.exitcode == 0
        @test occursin("PRK_RUNNER_SMOKE_OK nw=2", combined)
    end
end
