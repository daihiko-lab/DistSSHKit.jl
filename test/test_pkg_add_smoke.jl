using Test

@testset "julia -m SSHRunner runner via Pkg.develop (no vendored scripts)" begin
    kit_root = abspath(joinpath(@__DIR__, ".."))
    fixture = abspath(joinpath(@__DIR__, "fixtures", "runner_local_smoke.jl"))
    @test isfile(fixture)

    julia = joinpath(Sys.BINDIR, Base.julia_exename())

    mktempdir() do tmp
        proj = abspath(string(tmp))
        write(joinpath(proj, "Project.toml"), "name = \"SmokeAddApp\"\n")
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)

        # Register the kit as a normal dependency (path-based here; `Pkg.add(url=..., rev=...)`
        # in real usage resolves the same way once published, exercising the same code path).
        develop_cmd = setenv(
            `$julia --project=$proj -e "using Pkg; Pkg.develop(path=$(repr(kit_root)))"`,
            filter(!isempty, ENV),
        )
        develop_out = IOBuffer()
        develop_proc = run(pipeline(develop_cmd, stdout=develop_out, stderr=develop_out), wait=true)
        @test develop_proc.exitcode == 0

        run_cmd = setenv(
            `$julia --project=$proj -m SSHRunner runner --local 2 --no-log $script`,
            merge(filter(!isempty, ENV), Dict(
                "DISTRIBUTED_INIT_DELAY_SEC" => "0",
                "DISTRIBUTED_PROJECT_ROOT" => proj,
            )),
        )
        out = IOBuffer()
        proc = run(pipeline(run_cmd, stdout=out, stderr=out), wait=true)
        combined = String(take!(out))
        @test proc.exitcode == 0
        @test occursin("PRK_RUNNER_SMOKE_OK nw=2", combined)
    end
end
