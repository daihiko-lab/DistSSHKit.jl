using Test

@testset "script path" begin
    kit_root = abspath(joinpath(@__DIR__, ".."))
    runner = joinpath(kit_root, "src", "runner.jl")
    fixture = abspath(joinpath(@__DIR__, "fixtures", "runner_local_smoke.jl"))
    julia = joinpath(Sys.BINDIR, Base.julia_exename())

    mktempdir() do tmp
        proj = abspath(string(tmp))
        write(joinpath(proj, "Project.toml"), "name = \"SmokeLogApp\"\n")
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)
        log_dir = joinpath(proj, "logs")
        mkpath(log_dir)

        cmd = `$julia --project=$proj $runner --local 2 --log-dir $log_dir $script`
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
