using Test

@testset "path helpers" begin
    # -- short_path --------------------------------------------------------
    let home = expanduser("~")
        @test DistSSHKit.short_path(joinpath(home, "foo", "bar")) == joinpath("~", "foo", "bar")
        @test DistSSHKit.short_path("/not/under/home") == "/not/under/home"
    end

    # -- _project_toml_version ---------------------------------------------
    mktempdir() do tmp
        d = abspath(string(tmp))
        @test DistSSHKit._project_toml_version(joinpath(d, "Project.toml")) === nothing
        write(joinpath(d, "Project.toml"), "name = \"Foo\"\n")
        @test DistSSHKit._project_toml_version(joinpath(d, "Project.toml")) === nothing
        write(joinpath(d, "Project.toml"), "name = \"Foo\"\nversion = \"1.2.3\"\n")
        @test DistSSHKit._project_toml_version(joinpath(d, "Project.toml")) == v"1.2.3"
        write(joinpath(d, "Project.toml"), "version = \"not-a-version\"\n")
        @test DistSSHKit._project_toml_version(joinpath(d, "Project.toml")) === nothing
    end

    # -- resolve_pkg_project_dir: plain hit and fallback --------------------
    mktempdir() do tmp
        d = abspath(string(tmp))
        write(joinpath(d, "Project.toml"), "name = \"SoloApp\"\n")
        @test DistSSHKit.resolve_pkg_project_dir(d) == d
    end
    mktempdir() do tmp
        d = abspath(string(tmp))
        nested = joinpath(d, "a", "b", "c")
        mkpath(nested)
        @test DistSSHKit.resolve_pkg_project_dir(nested) == dirname(nested)
    end

    # -- runner_kit_project_root -------------------------------------------
    mktempdir() do tmp
        d = abspath(string(tmp))
        write(joinpath(d, "Project.toml"), "name = \"DistSSHKit\"\n")
        @test DistSSHKit.runner_kit_project_root(d) == d
        src = joinpath(d, "src")
        mkpath(src)
        @test DistSSHKit.runner_kit_project_root(src) == d
    end
    mktempdir() do tmp
        d = abspath(string(tmp))
        app = joinpath(d, "MyApp")
        kit = joinpath(app, "DistSSHKit")
        mkpath(kit)
        write(joinpath(app, "Project.toml"), "name = \"MyApp\"\n")
        write(joinpath(kit, "Project.toml"), "name = \"DistSSHKit\"\n")
        @test DistSSHKit.runner_kit_project_root(kit) == app
        src = joinpath(kit, "src")
        mkpath(src)
        @test DistSSHKit.runner_kit_project_root(src) == app
    end

    mktempdir() do tmp
        d = abspath(string(tmp))
        @test DistSSHKit.project_package_name(d) === nothing
        write(joinpath(d, "Project.toml"), "name = \"FooBar\"\n")
        @test DistSSHKit.project_package_name(d) == "FooBar"
    end

    mktempdir() do tmp
        root = abspath(string(tmp))
        mkpath(joinpath(root, "kitstub"))
        write(joinpath(root, "Project.toml"), "name = \"App\"\n")
        write(joinpath(root, "kitstub", "Project.toml"), "name = \"DistSSHKit\"\n")
        @test DistSSHKit.resolve_pkg_project_dir(joinpath(root, "kitstub")) == root
    end

    # -- resolve_pkg_project_dir: embedded app scripts, standalone kit, nested projects
    mktempdir() do tmp
        root = abspath(string(tmp))
        app = joinpath(root, "MyApp")
        kit = joinpath(app, "DistSSHKit")
        scripts = joinpath(app, "scripts", "jobs")
        mkpath(scripts)
        mkpath(joinpath(kit, "src"))
        write(joinpath(app, "Project.toml"), "name = \"MyApp\"\n")
        write(joinpath(kit, "Project.toml"), "name = \"DistSSHKit\"\n")
        @test DistSSHKit.resolve_pkg_project_dir(scripts) == app
        @test DistSSHKit.runner_kit_project_root(joinpath(kit, "src")) == app
        @test DistSSHKit.runner_kit_project_root(kit) == app
    end
    mktempdir() do tmp
        root = abspath(string(tmp))
        write(joinpath(root, "Project.toml"), "name = \"DistSSHKit\"\n")
        nested = joinpath(root, "templates")
        mkpath(nested)
        @test DistSSHKit.resolve_pkg_project_dir(nested) == root
        @test DistSSHKit.runner_kit_project_root(joinpath(root, "src")) == root
    end
    mktempdir() do tmp
        root = abspath(string(tmp))
        subpkg = joinpath(root, "SubPkg")
        script_dir = joinpath(subpkg, "src")
        mkpath(script_dir)
        write(joinpath(root, "Project.toml"), "name = \"MyApp\"\n")
        write(joinpath(subpkg, "Project.toml"), "name = \"SubPkg\"\n")
        @test DistSSHKit.resolve_pkg_project_dir(script_dir) == subpkg
    end
    mktempdir() do tmp
        root = abspath(string(tmp))
        kit = joinpath(root, "DistSSHKit")
        mkpath(joinpath(kit, "src"))
        write(joinpath(root, "Project.toml"), "name = \"HostApp\"\n")
        write(joinpath(kit, "Project.toml"), "name = \"DistSSHKit\"\n")
        # Scripts co-located with kit `src/` (runner.jl __DIR__) should inherit the host app root.
        @test DistSSHKit.resolve_pkg_project_dir(joinpath(kit, "src")) == root
        @test DistSSHKit.runner_kit_project_root(joinpath(kit, "src")) == root
    end

    @test DistSSHKit.dist_ssh_kit_version() >= v"0.2.1"

    @test DistSSHKit.normalize_git_clone_url("https://github.com/org/App.jl.git") ==
        "git@github.com:org/App.jl.git"
    @test DistSSHKit.normalize_git_clone_url("git@github.com:org/App.jl.git") ==
        "git@github.com:org/App.jl.git"

    @test DistSSHKit.default_remote_project_path("/Users/z/GitHub/MyApp.jl") ==
        joinpath("~", "GitHub", "MyApp.jl")

    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => nothing) do
        @test DistSSHKit.resolve_remote_project_root("/Users/z/GitHub/MyApp.jl") ==
            joinpath("~", "GitHub", "MyApp.jl")
    end
    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/Volumes/shared/MyApp.jl") do
        @test DistSSHKit.resolve_remote_project_root("/Users/z/GitHub/MyApp.jl") ==
            "/Volumes/shared/MyApp.jl"
    end
    @test DistSSHKit.resolve_remote_project_root(
            "/Users/z/GitHub/MyApp.jl";
            cli_override="~/work/MyApp.jl",
        ) == "~/work/MyApp.jl"
    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/Volumes/shared/MyApp.jl") do
        @test DistSSHKit.resolve_remote_project_root(
                "/Users/z/GitHub/MyApp.jl";
                cli_override="~/work/MyApp.jl",
            ) == "~/work/MyApp.jl"
    end

    @test DistSSHKit.local_dir_from_remote_mirror(
            "/Volumes/r/MyRepo/data/sweep/slug/20260101_120000",
            "/Volumes/r/MyRepo",
            "/Users/z/MyRepo",
        ) == joinpath("/Users/z/MyRepo", "data", "sweep", "slug", "20260101_120000") |> abspath

    @test DistSSHKit.remote_path_for_ssh_collect(
            "/Users/z/MyRepo/data/out",
            "/Users/z/MyRepo",
        ) == "/Users/z/MyRepo/data/out"
    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/Volumes/z/clone/MyRepo") do
        @test DistSSHKit.remote_path_for_ssh_collect(
                "/Users/z/MyRepo/data/sweep/x/ts",
                "/Users/z/MyRepo",
            ) == joinpath("/Volumes/z/clone/MyRepo", "data", "sweep", "x", "ts") |> abspath
    end

    mktempdir() do tmp
        d = abspath(string(tmp))
        nested = joinpath(d, "a", "b.txt")
        mkpath(dirname(nested))
        write(nested, "")
        @test DistSSHKit.display_path(nested, d) == joinpath("a", "b.txt")
    end

    mktempdir() do tmp
        repo = abspath(string(tmp))
        sd = joinpath(repo, "scripts")
        mkpath(sd)
        out2 = joinpath(repo, "nested", "out2")
        withenv(
            "DISTRIBUTED_COLLECT_DIRS" => "out1:$(out2)",
            "DISTRIBUTED_OUTPUT_DIR" => joinpath(repo, "ignored"),
        ) do
            roots = DistSSHKit.distributed_collect_root_dirs(sd, repo)
            @test roots == String[abspath(joinpath(repo, "out1")), abspath(out2)]
        end
        withenv(
            "DISTRIBUTED_COLLECT_DIRS" => "out1:out1",
            "DISTRIBUTED_OUTPUT_DIR" => joinpath(repo, "ignored"),
        ) do
            roots = DistSSHKit.distributed_collect_root_dirs(sd, repo)
            @test roots == String[abspath(joinpath(repo, "out1"))]
        end
        withenv(
            "DISTRIBUTED_COLLECT_DIRS" => "",
            "DISTRIBUTED_OUTPUT_DIR" => joinpath(repo, "solo"),
        ) do
            @test DistSSHKit.distributed_collect_root_dirs(sd, repo) ==
                String[abspath(joinpath(repo, "solo"))]
        end
    end

    # -- build_ssh_opts ------------------------------------------------------
    withenv("DISTRIBUTED_SSH_OPTS" => nothing) do
        opts = DistSSHKit.build_ssh_opts()
        @test "-o" in opts
        @test "BatchMode=yes" in opts
    end
    withenv("DISTRIBUTED_SSH_OPTS" => "-o Foo=bar -o Baz=qux") do
        @test DistSSHKit.build_ssh_opts() == ["-o", "Foo=bar", "-o", "Baz=qux"]
    end

    # -- get_local_resources ---------------------------------------------
    let r = DistSSHKit.get_local_resources()
        @test r.total_gb > 0
        @test r.nproc >= 1
    end

    # -- TeeIO ---------------------------------------------------------------
    let primary = IOBuffer(), secondary = IOBuffer()
        tee = DistSSHKit.TeeIO(primary, secondary)
        write(tee, Vector{UInt8}(codeunits("line1\r")))  # \r discards buffered line (progress-bar overwrite)
        write(tee, Vector{UInt8}(codeunits("line2\n")))
        write(tee, UInt8['a', 'b', 0x0a])
        flush(tee)
        @test String(take!(primary)) == "line1\rline2\nab\n"
        @test String(take!(secondary)) == "line2\nab\n"
    end
    let primary = IOBuffer(), secondary = IOBuffer()
        tee = DistSSHKit.TeeIO(primary, secondary)
        write(tee, Vector{UInt8}(codeunits("partial")))  # no trailing newline yet
        @test String(take!(secondary)) == ""
        flush(tee)                     # flush should emit the trailing partial line
        @test String(take!(secondary)) == "partial"
    end
    let primary = IOBuffer()
        tee = DistSSHKit.TeeIO(primary, nothing)
        write(tee, Vector{UInt8}(codeunits("hello\n")))
        @test String(take!(primary)) == "hello\n"
    end

    # -- get_local_git_hash / clone_url_from_local_origin ----------------------
    mktempdir() do tmp
        d = abspath(string(tmp))
        @test DistSSHKit.get_local_git_hash(d) === nothing
        @test DistSSHKit.clone_url_from_local_origin(d) === nothing

        run(Cmd(["git", "-C", d, "init", "-q"]))
        run(Cmd(["git", "-C", d, "config", "user.email", "test@example.com"]))
        run(Cmd(["git", "-C", d, "config", "user.name", "Test"]))
        write(joinpath(d, "f.txt"), "hi")
        run(Cmd(["git", "-C", d, "add", "f.txt"]))
        run(Cmd(["git", "-C", d, "commit", "-q", "-m", "init"]))

        full = DistSSHKit.get_local_git_hash(d)
        @test full isa String
        @test full isa String && length(full) == 40
        short = DistSSHKit.get_local_git_hash(d; short=8)
        @test short isa String
        @test short isa String && length(short) == 8
        @test full isa String && short isa String && startswith(full, short)

        run(Cmd(["git", "-C", d, "remote", "add", "origin", "https://github.com/org/App.jl.git"]))
        @test DistSSHKit.clone_url_from_local_origin(d) == "git@github.com:org/App.jl.git"
    end

    # -- CLI script bridge (_run_kit_cli_script; backs `runner()`/`(@main)`) --
    let fixture = abspath(joinpath(@__DIR__, "fixtures", "cli_echo_args.jl"))
        # Regression: app launcher may pass `ARGS` itself; must not empty before snapshot.
        mktemp() do args_file, _
            withenv(
                "DISTRIBUTED_PROJECT_ROOT" => "/override",
                "_PRK_TEST_ARGS_FILE" => args_file,
            ) do
                empty!(ARGS)
                append!(ARGS, ["--local", "2", "job.jl"])
                @test DistSSHKit._run_kit_cli_script(fixture, ARGS) == 0
                @test readlines(args_file) == ["--local", "2", "job.jl"]
            end
        end

        mktempdir() do tmp
            mktemp() do args_file, _
                withenv(
                    "DISTRIBUTED_PROJECT_ROOT" => nothing,
                    "_PRK_TEST_ARGS_FILE" => args_file,
                ) do
                    cd(tmp) do
                        empty!(ARGS)
                        @test DistSSHKit._run_kit_cli_script(fixture, ["probe"]) == 0
                        @test realpath(ENV["DISTRIBUTED_PROJECT_ROOT"]) == realpath(tmp)
                        @test readlines(args_file) == ["probe"]
                    end
                end
            end
        end
    end
end
