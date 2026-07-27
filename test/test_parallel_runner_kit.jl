using Test

@testset "ParallelRunnerKit (path helpers)" begin
    include(joinpath(@__DIR__, "..", "src", "ParallelRunnerKit.jl"))
    using .ParallelRunnerKit

    # -- short_path --------------------------------------------------------
    let home = expanduser("~")
        @test short_path(joinpath(home, "foo", "bar")) == joinpath("~", "foo", "bar")
        @test short_path("/not/under/home") == "/not/under/home"
    end

    # -- _project_toml_version ---------------------------------------------
    mktempdir() do tmp
        d = abspath(string(tmp))
        @test ParallelRunnerKit._project_toml_version(joinpath(d, "Project.toml")) === nothing
        write(joinpath(d, "Project.toml"), "name = \"Foo\"\n")
        @test ParallelRunnerKit._project_toml_version(joinpath(d, "Project.toml")) === nothing
        write(joinpath(d, "Project.toml"), "name = \"Foo\"\nversion = \"1.2.3\"\n")
        @test ParallelRunnerKit._project_toml_version(joinpath(d, "Project.toml")) == v"1.2.3"
        write(joinpath(d, "Project.toml"), "version = \"not-a-version\"\n")
        @test ParallelRunnerKit._project_toml_version(joinpath(d, "Project.toml")) === nothing
    end

    # -- resolve_pkg_project_dir: plain hit and fallback --------------------
    mktempdir() do tmp
        d = abspath(string(tmp))
        write(joinpath(d, "Project.toml"), "name = \"SoloApp\"\n")
        @test resolve_pkg_project_dir(d) == d
    end
    mktempdir() do tmp
        d = abspath(string(tmp))
        nested = joinpath(d, "a", "b", "c")
        mkpath(nested)
        @test resolve_pkg_project_dir(nested) == dirname(nested)
    end

    # -- runner_kit_project_root -------------------------------------------
    mktempdir() do tmp
        d = abspath(string(tmp))
        write(joinpath(d, "Project.toml"), "name = \"ParallelRunnerKit\"\n")
        @test runner_kit_project_root(d) == d
        src = joinpath(d, "src")
        mkpath(src)
        @test runner_kit_project_root(src) == d
    end
    mktempdir() do tmp
        d = abspath(string(tmp))
        app = joinpath(d, "MyApp")
        kit = joinpath(app, "ParallelRunnerKit")
        mkpath(kit)
        write(joinpath(app, "Project.toml"), "name = \"MyApp\"\n")
        write(joinpath(kit, "Project.toml"), "name = \"ParallelRunnerKit\"\n")
        @test runner_kit_project_root(kit) == app
        src = joinpath(kit, "src")
        mkpath(src)
        @test runner_kit_project_root(src) == app
    end

    mktempdir() do tmp
        d = abspath(string(tmp))
        @test project_package_name(d) === nothing
        write(joinpath(d, "Project.toml"), "name = \"FooBar\"\n")
        @test project_package_name(d) == "FooBar"
    end

    mktempdir() do tmp
        root = abspath(string(tmp))
        mkpath(joinpath(root, "kitstub"))
        write(joinpath(root, "Project.toml"), "name = \"App\"\n")
        write(joinpath(root, "kitstub", "Project.toml"), "name = \"ParallelRunnerKit\"\n")
        @test resolve_pkg_project_dir(joinpath(root, "kitstub")) == root
    end

    # -- resolve_pkg_project_dir: embedded app scripts, standalone kit, nested projects
    mktempdir() do tmp
        root = abspath(string(tmp))
        app = joinpath(root, "MyApp")
        kit = joinpath(app, "ParallelRunnerKit")
        scripts = joinpath(app, "scripts", "jobs")
        mkpath(scripts)
        mkpath(joinpath(kit, "src"))
        write(joinpath(app, "Project.toml"), "name = \"MyApp\"\n")
        write(joinpath(kit, "Project.toml"), "name = \"ParallelRunnerKit\"\n")
        @test resolve_pkg_project_dir(scripts) == app
        @test runner_kit_project_root(joinpath(kit, "src")) == app
        @test runner_kit_project_root(kit) == app
    end
    mktempdir() do tmp
        root = abspath(string(tmp))
        write(joinpath(root, "Project.toml"), "name = \"ParallelRunnerKit\"\n")
        nested = joinpath(root, "templates")
        mkpath(nested)
        @test resolve_pkg_project_dir(nested) == root
        @test runner_kit_project_root(joinpath(root, "src")) == root
    end
    mktempdir() do tmp
        root = abspath(string(tmp))
        subpkg = joinpath(root, "SubPkg")
        script_dir = joinpath(subpkg, "src")
        mkpath(script_dir)
        write(joinpath(root, "Project.toml"), "name = \"MyApp\"\n")
        write(joinpath(subpkg, "Project.toml"), "name = \"SubPkg\"\n")
        @test resolve_pkg_project_dir(script_dir) == subpkg
    end
    mktempdir() do tmp
        root = abspath(string(tmp))
        kit = joinpath(root, "ParallelRunnerKit")
        mkpath(joinpath(kit, "src"))
        write(joinpath(root, "Project.toml"), "name = \"HostApp\"\n")
        write(joinpath(kit, "Project.toml"), "name = \"ParallelRunnerKit\"\n")
        # Scripts co-located with kit `src/` (runner.jl __DIR__) should inherit the host app root.
        @test resolve_pkg_project_dir(joinpath(kit, "src")) == root
        @test runner_kit_project_root(joinpath(kit, "src")) == root
    end

    @test parallel_runner_kit_version() >= v"0.2.1"

    @test ParallelRunnerKit.normalize_git_clone_url("https://github.com/org/App.jl.git") ==
        "git@github.com:org/App.jl.git"
    @test ParallelRunnerKit.normalize_git_clone_url("git@github.com:org/App.jl.git") ==
        "git@github.com:org/App.jl.git"

    @test ParallelRunnerKit.default_remote_project_path("/Users/z/GitHub/MyApp.jl") ==
        joinpath("~", "GitHub", "MyApp.jl")

    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => nothing) do
        @test ParallelRunnerKit.resolve_remote_project_root("/Users/z/GitHub/MyApp.jl") ==
            joinpath("~", "GitHub", "MyApp.jl")
    end
    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/Volumes/shared/MyApp.jl") do
        @test ParallelRunnerKit.resolve_remote_project_root("/Users/z/GitHub/MyApp.jl") ==
            "/Volumes/shared/MyApp.jl"
    end
    @test ParallelRunnerKit.resolve_remote_project_root(
            "/Users/z/GitHub/MyApp.jl";
            cli_override="~/work/MyApp.jl",
        ) == "~/work/MyApp.jl"
    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/Volumes/shared/MyApp.jl") do
        @test ParallelRunnerKit.resolve_remote_project_root(
                "/Users/z/GitHub/MyApp.jl";
                cli_override="~/work/MyApp.jl",
            ) == "~/work/MyApp.jl"
    end

    @test_throws ArgumentError ParallelRunnerKit.parse_runner_args(["--collect", "h"])
    @test_throws ArgumentError ParallelRunnerKit.parse_runner_args(["--collect-sync", "data/sweep", "host"])

    let r = ParallelRunnerKit.parse_runner_args(["--collect-missing", "data/sweep", "host-a", "host-b"])
        @test r.collect_root == abspath("data/sweep")
        @test r.collect_hosts == ["host-a", "host-b"]
        @test r.collect_overwrite == false
        @test r.script_path === nothing
    end

    let r = ParallelRunnerKit.parse_runner_args(["--collect-tree", "data/sweep", "host-a", "host-b"])
        @test r.collect_root == abspath("data/sweep")
        @test r.collect_hosts == ["host-a", "host-b"]
        @test r.collect_overwrite == false
    end

    let r = ParallelRunnerKit.parse_runner_args(["--collect-overwrite", "data/sweep", "host-a"])
        @test r.collect_root == abspath("data/sweep")
        @test r.collect_hosts == ["host-a"]
        @test r.collect_overwrite == true
    end

    let r = ParallelRunnerKit.parse_runner_args(["--collect-tree-sync", "data/sweep", "host-a"])
        @test r.collect_root == abspath("data/sweep")
        @test r.collect_hosts == ["host-a"]
        @test r.collect_overwrite == true
    end

    @test_throws ArgumentError ParallelRunnerKit.parse_runner_args(["--collect-missing", "data/sweep"])

    @test ParallelRunnerKit.local_dir_from_remote_mirror(
            "/Volumes/r/MyRepo/data/sweep/slug/20260101_120000",
            "/Volumes/r/MyRepo",
            "/Users/z/MyRepo",
        ) == joinpath("/Users/z/MyRepo", "data", "sweep", "slug", "20260101_120000") |> abspath

    @test ParallelRunnerKit.remote_path_for_ssh_collect(
            "/Users/z/MyRepo/data/out",
            "/Users/z/MyRepo",
        ) == "/Users/z/MyRepo/data/out"
    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/Volumes/z/clone/MyRepo") do
        @test ParallelRunnerKit.remote_path_for_ssh_collect(
                "/Users/z/MyRepo/data/sweep/x/ts",
                "/Users/z/MyRepo",
            ) == joinpath("/Volumes/z/clone/MyRepo", "data", "sweep", "x", "ts") |> abspath
    end

    mktempdir() do tmp
        d = abspath(string(tmp))
        nested = joinpath(d, "a", "b.txt")
        mkpath(dirname(nested))
        write(nested, "")
        @test display_path(nested, d) == joinpath("a", "b.txt")
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
            roots = ParallelRunnerKit.distributed_collect_root_dirs(sd, repo)
            @test roots == String[abspath(joinpath(repo, "out1")), abspath(out2)]
        end
        withenv(
            "DISTRIBUTED_COLLECT_DIRS" => "out1:out1",
            "DISTRIBUTED_OUTPUT_DIR" => joinpath(repo, "ignored"),
        ) do
            roots = ParallelRunnerKit.distributed_collect_root_dirs(sd, repo)
            @test roots == String[abspath(joinpath(repo, "out1"))]
        end
        withenv(
            "DISTRIBUTED_COLLECT_DIRS" => "",
            "DISTRIBUTED_OUTPUT_DIR" => joinpath(repo, "solo"),
        ) do
            @test ParallelRunnerKit.distributed_collect_root_dirs(sd, repo) ==
                String[abspath(joinpath(repo, "solo"))]
        end
    end

    # -- build_ssh_opts ------------------------------------------------------
    withenv("DISTRIBUTED_SSH_OPTS" => nothing) do
        opts = ParallelRunnerKit.build_ssh_opts()
        @test "-o" in opts
        @test "BatchMode=yes" in opts
    end
    withenv("DISTRIBUTED_SSH_OPTS" => "-o Foo=bar -o Baz=qux") do
        @test ParallelRunnerKit.build_ssh_opts() == ["-o", "Foo=bar", "-o", "Baz=qux"]
    end

    # -- estimate_worker_memory_gb / estimate_available_gb -------------------
    @test ParallelRunnerKit.estimate_worker_memory_gb() > 0
    let (total, avail) = ParallelRunnerKit.estimate_available_gb()
        @test total > 0
        @test avail > 0
        @test avail <= total || avail == total * 0.5
    end

    # -- get_local_resources ---------------------------------------------
    let r = ParallelRunnerKit.get_local_resources()
        @test r.total_gb > 0
        @test r.nproc >= 1
    end

    # -- _parse_host_workers_spec ---------------------------------------
    @test ParallelRunnerKit._parse_host_workers_spec("host-a") == ("host-a", nothing)
    @test ParallelRunnerKit._parse_host_workers_spec("host-a:10") == ("host-a", 10)

    # -- TeeIO ---------------------------------------------------------------
    let primary = IOBuffer(), secondary = IOBuffer()
        tee = ParallelRunnerKit.TeeIO(primary, secondary)
        write(tee, Vector{UInt8}(codeunits("line1\r")))  # \r discards buffered line (progress-bar overwrite)
        write(tee, Vector{UInt8}(codeunits("line2\n")))
        write(tee, UInt8['a', 'b', 0x0a])
        flush(tee)
        @test String(take!(primary)) == "line1\rline2\nab\n"
        @test String(take!(secondary)) == "line2\nab\n"
    end
    let primary = IOBuffer(), secondary = IOBuffer()
        tee = ParallelRunnerKit.TeeIO(primary, secondary)
        write(tee, Vector{UInt8}(codeunits("partial")))  # no trailing newline yet
        @test String(take!(secondary)) == ""
        flush(tee)                     # flush should emit the trailing partial line
        @test String(take!(secondary)) == "partial"
    end
    let primary = IOBuffer()
        tee = ParallelRunnerKit.TeeIO(primary, nothing)
        write(tee, Vector{UInt8}(codeunits("hello\n")))
        @test String(take!(primary)) == "hello\n"
    end

    # -- parse_runner_args: basic options -----------------------------------
    withenv("JULIA_DISTRIBUTED_EXE" => nothing) do
        let r = ParallelRunnerKit.parse_runner_args(["--help"])
            @test r.help == true
        end
        let r = ParallelRunnerKit.parse_runner_args(["-h"])
            @test r.help == true
        end
        let r = ParallelRunnerKit.parse_runner_args(["--local", "4", "myscript.jl", "a", "b"])
            @test r.local_workers == 4
            @test r.script_path == "myscript.jl"
            @test r.script_args == ["a", "b"]
            @test r.help == false
        end
        let r = ParallelRunnerKit.parse_runner_args(["--workers", "3", "host1", "host2:5", "s.jl"])
            @test r.default_workers == 3
            @test r.hosts == [("host1", nothing), ("host2", 5)]
            @test r.script_path == "s.jl"
        end
        let r = ParallelRunnerKit.parse_runner_args(["--julia", "/usr/bin/julia", "s.jl"])
            @test r.julia == "/usr/bin/julia"
        end
        let r = ParallelRunnerKit.parse_runner_args(["--julia", "auto", "s.jl"])
            @test r.julia === nothing
        end
        let r = ParallelRunnerKit.parse_runner_args(["--skip-hash-check", "s.jl"])
            @test r.skip_hash_check == true
        end
        let r = ParallelRunnerKit.parse_runner_args(["--no-hash-check", "s.jl"])
            @test r.skip_hash_check == true
        end
        let r = ParallelRunnerKit.parse_runner_args(["--no-log", "s.jl"])
            @test r.enable_log == false
        end
        let r = ParallelRunnerKit.parse_runner_args(["--log-dir", "/tmp/logs", "s.jl"])
            @test r.log_dir == "/tmp/logs"
        end
        let r = ParallelRunnerKit.parse_runner_args(["--package", "MyPkg", "s.jl"])
            @test r.explicit_package == "MyPkg"
        end
        let r = ParallelRunnerKit.parse_runner_args(["--package", "  ", "s.jl"])
            @test r.explicit_package === nothing
        end
        let r = ParallelRunnerKit.parse_runner_args(String[])
            @test r.script_path === nothing
            @test r.help == false
        end
    end
    withenv("JULIA_DISTRIBUTED_EXE" => "/opt/custom/julia") do
        let r = ParallelRunnerKit.parse_runner_args(["s.jl"])
            @test r.julia == "/opt/custom/julia"
        end
    end

    # -- runner_help_text ----------------------------------------------
    let txt = ParallelRunnerKit.runner_help_text()
        @test occursin("Usage:", txt)
        @test occursin("--collect-missing", txt)
        @test occursin("JULIA_DISTRIBUTED_EXE", txt)
    end

    # -- get_local_git_hash / clone_url_from_local_origin / check_git_hashes
    mktempdir() do tmp
        d = abspath(string(tmp))
        @test ParallelRunnerKit.get_local_git_hash(d) === nothing
        @test ParallelRunnerKit.clone_url_from_local_origin(d) === nothing
        ok_flag, mismatches = ParallelRunnerKit.check_git_hashes(String[], d)
        @test ok_flag == true
        @test mismatches == String[]

        run(Cmd(["git", "-C", d, "init", "-q"]))
        run(Cmd(["git", "-C", d, "config", "user.email", "test@example.com"]))
        run(Cmd(["git", "-C", d, "config", "user.name", "Test"]))
        write(joinpath(d, "f.txt"), "hi")
        run(Cmd(["git", "-C", d, "add", "f.txt"]))
        run(Cmd(["git", "-C", d, "commit", "-q", "-m", "init"]))

        full = ParallelRunnerKit.get_local_git_hash(d)
        @test full isa String
        @test full isa String && length(full) == 40
        short = ParallelRunnerKit.get_local_git_hash(d; short=8)
        @test short isa String
        @test short isa String && length(short) == 8
        @test full isa String && short isa String && startswith(full, short)

        run(Cmd(["git", "-C", d, "remote", "add", "origin", "https://github.com/org/App.jl.git"]))
        @test ParallelRunnerKit.clone_url_from_local_origin(d) == "git@github.com:org/App.jl.git"
    end

    # -- Pkg app bridge (_run_kit_cli_script) -----------------------------
    @test isdefined(ParallelRunnerKit, :AppRunner)
    @test isdefined(ParallelRunnerKit, :AppSetup)
    @test isdefined(ParallelRunnerKit, :AppSuggest)

    let fixture = abspath(joinpath(@__DIR__, "fixtures", "cli_echo_args.jl"))
        # Regression: app launcher may pass `ARGS` itself; must not empty before snapshot.
        mktemp() do args_file, _
            withenv(
                "DISTRIBUTED_PROJECT_ROOT" => "/override",
                "_PRK_TEST_ARGS_FILE" => args_file,
            ) do
                empty!(ARGS)
                append!(ARGS, ["--local", "2", "job.jl"])
                @test ParallelRunnerKit._run_kit_cli_script(fixture, ARGS) == 0
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
                        @test ParallelRunnerKit._run_kit_cli_script(fixture, ["probe"]) == 0
                        @test realpath(ENV["DISTRIBUTED_PROJECT_ROOT"]) == realpath(tmp)
                        @test readlines(args_file) == ["probe"]
                    end
                end
            end
        end
    end
end

@testset "Pkg [apps] in Project.toml" begin
    using TOML
    apps = get(TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml")), "apps", Dict{String,Any}())
    @test get(get(apps, "prunner", Dict()), "submodule", "") == "AppRunner"
    @test get(get(apps, "psetup", Dict()), "submodule", "") == "AppSetup"
    @test get(get(apps, "psuggest", Dict()), "submodule", "") == "AppSuggest"
end

@testset "host Project.toml merges kit [deps] (monorepo layout)" begin
    using TOML
    kit_root = abspath(joinpath(@__DIR__, ".."))
    kit_toml = joinpath(kit_root, "Project.toml")
    @test isfile(kit_toml)
    kit_deps = get(TOML.parsefile(kit_toml), "deps", Dict{String,String}())
    parent = dirname(kit_root)
    parent_proj = joinpath(parent, "Project.toml")
    nested_kit = joinpath(parent, "ParallelRunnerKit", "Project.toml")
    # Monorepo: `.../App/ParallelRunnerKit/test` → kit at `App/ParallelRunnerKit`, host `App/Project.toml`.
    # Standalone kit repo: parent has no nested `ParallelRunnerKit/Project.toml`; only assert kit deps exist.
    skip_merge_check = ["Distributed"]
    if isfile(parent_proj) && isfile(nested_kit) && abspath(kit_root) == abspath(joinpath(parent, "ParallelRunnerKit"))
        root_deps = get(TOML.parsefile(parent_proj), "deps", Dict{String,String}())
        for (name, uuid) in kit_deps
            n = String(name)
            n in skip_merge_check && continue
            @test haskey(root_deps, n)
            @test root_deps[n] == String(uuid)
        end
    else
        @test haskey(kit_deps, "ArgParse")
        @test haskey(kit_deps, "JSON3")
    end
end
