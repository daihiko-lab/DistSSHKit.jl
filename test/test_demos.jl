using Test

function _run_runner_demo(;
    julia::String,
    kit_root::String,
    script::String,
    local_workers::Int=2,
)
    cmd = setenv(
        `$julia --project=$kit_root -m SSHRunner runner --local $local_workers --no-log $script`,
        merge(filter(!isempty, ENV), Dict(
            "DISTRIBUTED_INIT_DELAY_SEC" => "0",
            "DISTRIBUTED_PROJECT_ROOT" => kit_root,
        )),
    )
    out = IOBuffer()
    proc = run(pipeline(cmd, stdout=out, stderr=out), wait=true)
    return proc, String(take!(out))
end

function _stage_demos!(dest_dir::String, kit_root::String)
    for name in ("param_sweep.jl", "coin_flip.jl")
        src = joinpath(kit_root, "demos", name)
        @test isfile(src)
        cp(src, joinpath(dest_dir, name); force=true)
    end
end

@testset "demos" begin
    kit_root = abspath(joinpath(@__DIR__, ".."))
    julia = joinpath(Sys.BINDIR, Base.julia_exename())

    mktempdir() do tmp
        demos_dir = joinpath(tmp, "demos")
        mkpath(demos_dir)
        _stage_demos!(demos_dir, kit_root)

        sweep_script = joinpath(demos_dir, "param_sweep.jl")
        sweep_proc, sweep_out = _run_runner_demo(;
            julia=julia,
            kit_root=kit_root,
            script=sweep_script,
        )
        @test sweep_proc.exitcode == 0
        @test occursin("Results:", sweep_out)

        sweep_csv = joinpath(demos_dir, "output", "sweep_results.csv")
        @test isfile(sweep_csv)
        expected = join([
            "param,result",
            ("$n,$(n^2)" for n in 1:8)...,
        ], '\n') * '\n'
        @test read(sweep_csv, String) == expected
        @test occursin("wrote ", sweep_out)

        flip_script = joinpath(demos_dir, "coin_flip.jl")
        flip_proc, flip_out = _run_runner_demo(;
            julia=julia,
            kit_root=kit_root,
            script=flip_script,
        )
        @test flip_proc.exitcode == 0
        @test occursin("Results:", flip_out)

        heads_line = nothing
        for line in split(flip_out, '\n')
            line = strip(line)
            if startswith(line, '[') && endswith(line, ']')
                heads_line = line
                break
            end
        end
        @test heads_line !== nothing
        parsed = Meta.parse(heads_line)
        heads_counts = if parsed isa AbstractVector
            Int.(parsed)
        elseif parsed isa Expr && parsed.head === :vect
            Int.(parsed.args)
        else
            nothing
        end
        @test heads_counts !== nothing
        @test length(heads_counts) == 4
        @test all(0 .<= heads_counts .<= 100)
    end
end
