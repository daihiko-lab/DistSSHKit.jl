using Test

@testset "-m DistSSHKit" begin
    kit_root = abspath(joinpath(@__DIR__, ".."))
    fixture = abspath(joinpath(@__DIR__, "fixtures", "runner_local_smoke.jl"))
    julia = joinpath(Sys.BINDIR, Base.julia_exename())

    mktempdir() do tmp
        proj = abspath(string(tmp))
        write(joinpath(proj, "Project.toml"), "name = \"SmokeLogAddApp\"\n")
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)
        log_dir = joinpath(proj, "logs")
        mkpath(log_dir)

        develop_cmd = setenv(
            `$julia --project=$proj -e "using Pkg; Pkg.develop(path=$(repr(kit_root)))"`,
            filter(!isempty, ENV),
        )
        develop_out = IOBuffer()
        develop_proc = run(pipeline(develop_cmd, stdout=develop_out, stderr=develop_out), wait=true)
        @test develop_proc.exitcode == 0

        cmd = `$julia --project=$proj -m DistSSHKit runner --local 2 --log-dir $log_dir $script`
        _assert_runner_log_output(;
            cmd=setenv(
                cmd,
                merge(filter(!isempty, ENV), Dict(
                    "DISTRIBUTED_INIT_DELAY_SEC" => "0",
                    "DISTRIBUTED_PROJECT_ROOT" => proj,
                )),
            ),
            log_dir=log_dir,
        )
    end
end
