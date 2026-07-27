# Bundled demo scripts (`demos/param_sweep.jl`, `demos/coin_flip.jl`, …): discovery
# and the `demo install` / `demo list` CLI subcommand. `_KIT_ROOT` is defined in the
# top-level `DistSSHKit.jl` (its `@__DIR__` must resolve to `src/`).

"""Directory containing bundled demo driver scripts (`param_sweep.jl`, `coin_flip.jl`, …)."""
demos_dir()::String = joinpath(_KIT_ROOT, "demos")

"""Names of bundled demos (without `.jl`), sorted."""
function list_demos()::Vector{String}
    dir = demos_dir()
    isdir(dir) || return String[]
    names = String[]
    for entry in readdir(dir)
        endswith(entry, ".jl") || continue
        push!(names, replace(basename(entry), ".jl" => ""))
    end
    return sort(names)
end

"""
    demo_script(name) -> Union{String, Nothing}

Absolute path to a bundled demo script. `name` may be `param_sweep` or `param_sweep.jl`.
Returns `nothing` when no such demo exists.
"""
function demo_script(name::AbstractString)::Union{Nothing,String}
    base = basename(String(name))
    endswith(base, ".jl") || (base = base * ".jl")
    path = joinpath(demos_dir(), base)
    return isfile(path) ? path : nothing
end

"""
    install_demos(dest=pwd(); force=false) -> (installed=Vector{String}, skipped=Vector{String})

Copy bundled demo driver scripts into `joinpath(dest, "demos")`.
Returns the paths written (`installed`) and the paths left untouched because a file
already existed there (`skipped`, only ever non-empty when `force=false`). Also
copies `demos/.gitignore` when present (subject to the same skip/force rule).

By default, existing files at the destination are left alone (e.g. demos you already
installed and edited, or an unrelated `demos/` folder in your project) — pass
`force=true` to overwrite them anyway.

If `dest/demos` would be the package's own bundled `demos/` directory (e.g. running
`demo install` from a checkout of this kit), throws `ArgumentError` — use
`demo list` to see bundled paths, or `demo install --dest DIR` to copy elsewhere.
"""
function install_demos(dest::AbstractString=pwd(); force::Bool=false)
    src::String = demos_dir()
    isdir(src) || return (installed=String[], skipped=String[])
    dest_root = abspath(expanduser(String(dest)))
    dest_demos = joinpath(dest_root, "demos")
    if abspath(dest_demos) == abspath(src)
        throw(ArgumentError(
            "destination would be the package's bundled demos/ ($src); " *
            "use `demo list` to see paths, or `demo install --dest DIR` to copy elsewhere",
        ))
    end
    mkpath(dest_demos)
    installed = String[]
    skipped = String[]
    entries::Vector{String} = readdir(src)
    for entry in sort(entries)
        endswith(entry, ".jl") || continue
        from = abspath(joinpath(src, entry))
        out = abspath(joinpath(dest_demos, entry))
        if !force && isfile(out)
            push!(skipped, out)
            continue
        end
        cp(from, out; force=true)
        push!(installed, out)
    end
    gitignore = joinpath(src, ".gitignore")
    if isfile(gitignore)
        gitignore_out = joinpath(dest_demos, ".gitignore")
        if !force && isfile(gitignore_out)
            push!(skipped, gitignore_out)
        else
            cp(gitignore, gitignore_out; force=true)
        end
    end
    return (installed=installed, skipped=skipped)
end

function _demo_install_args(args::Vector{String})::@NamedTuple{dest::String, force::Bool}
    dest = abspath(expanduser(get(ENV, "DISTRIBUTED_PROJECT_ROOT", pwd())))
    force = false
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--dest"
            i == length(args) && throw(ArgumentError("--dest requires a DIR argument"))
            dest = abspath(expanduser(args[i+1]))
            i += 2
        elseif arg == "--force"
            force = true
            i += 1
        else
            throw(ArgumentError("unknown option: $arg (supported: --dest DIR, --force)"))
        end
    end
    return (dest=dest, force=force)
end

function _demo_help_text()::String
    lines = String[
        "Usage:",
        "  julia --project=. -m DistSSHKit demo install [--dest DIR] [--force]",
        "  julia --project=. -m DistSSHKit demo list",
        "",
        "install  Copy bundled demo scripts into ./demos/ (or --dest DIR/demos/)",
        "         so you can read and edit them as templates. Existing files at",
        "         the destination are left alone; pass --force to overwrite them",
        "         (e.g. to reset an edited demo back to the bundled one).",
        "list     Show bundled demo names and their paths in the package.",
        "",
        "Bundled demos:",
    ]
    for name in list_demos()
        push!(lines, "  $name")
    end
    append!(lines, String[
        "",
        "After install, open demos/*.jl in your editor, then run for example:",
        "  julia --project=. -m DistSSHKit runner --local 2 demos/param_sweep.jl",
    ])
    return join(lines, '\n')
end

"""
    demo(args::Vector{String}=copy(ARGS))

Install or list bundled demo driver scripts. See [`(@main)`](@ref).

    julia --project=. -m DistSSHKit demo install
    julia --project=. -m DistSSHKit runner --local 2 demos/param_sweep.jl
"""
function demo(args::Vector{String}=copy(ARGS))::Cint
    if isempty(args) || args[1] in ("-h", "--help", "help")
        println(_demo_help_text())
        return 0
    end
    sub, rest = args[1], args[2:end]
    if sub == "list"
        for name in list_demos()
            path = demo_script(name)
            path === nothing && continue
            println(name, "\t", path)
        end
        return 0
    elseif sub == "install"
        try
            dest, force = _demo_install_args(rest)
            if isempty(list_demos())
                println(stderr, "No demo scripts found in package (", demos_dir(), ")")
                return 1
            end
            result = install_demos(dest; force=force)
            for path in result.installed
                println("wrote ", path)
            end
            for path in result.skipped
                println("skipped (already exists, use --force to overwrite): ", path)
            end
            dest_demos = if !isempty(result.installed)
                dirname(first(result.installed))
            elseif !isempty(result.skipped)
                dirname(first(result.skipped))
            else
                joinpath(dest, "demos")
            end
            rel_demos = relpath(dest_demos, dest)
            println()
            println("Demos are in ", dest_demos, "; open and edit them, then run for example:")
            println("  julia --project=. -m DistSSHKit runner --local 2 $rel_demos/param_sweep.jl")
            return 0
        catch err
            println(stderr, sprint(showerror, err))
            return 1
        end
    else
        println(stderr, "Unknown demo command: $sub (try: demo install, demo list, demo --help)")
        return 1
    end
end
