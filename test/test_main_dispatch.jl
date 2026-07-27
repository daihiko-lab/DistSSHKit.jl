using Test

@testset "(@main) dispatch" begin
    # `julia -m SSHRunner` invokes this module's `main` (the `(@main)` entry point).
    # Redirect CLI help text so test output stays readable.
    function _main_quiet(args)
        redirect_stdout(devnull) do
            redirect_stderr(devnull) do
                return SSHRunner.main(args)
            end
        end
    end
    @test _main_quiet(String[]) == 1
    @test _main_quiet(["bogus"]) == 1
    @test _main_quiet(["runner", "--help"]) == 0
    @test _main_quiet(["setup", "--help"]) == 0
    @test _main_quiet(["suggest-workers", "--help"]) == 0
    @test _main_quiet(["suggest_workers", "--help"]) == 0
end
