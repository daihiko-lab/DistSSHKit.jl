"""Run a local runner subprocess with logging enabled; assert console + log contents."""
function _assert_runner_log_output(; cmd::Cmd, log_dir::String)
    out = IOBuffer()
    proc = run(pipeline(setenv(cmd), stdout=out, stderr=out), wait=true)
    combined = String(take!(out))

    @test proc.exitcode == 0
    @test occursin("PRK_RUNNER_SMOKE_OK nw=2", combined)
    @test occursin("Results:", combined)

    log_files = String[
        name for name in readdir(log_dir)
        if startswith(name, "runner_") && endswith(name, ".log")
    ]
    @test length(log_files) == 1
    log_content = read(joinpath(log_dir, only(log_files)), String)

    for needle in (
        "Script:",
        "Workers:",
        "Running script...",
        "PRK_RUNNER_SMOKE_OK nw=2",
        "Results:",
    )
        @test occursin(needle, log_content)
    end

    return combined, log_content
end
