# =============================================================================
# Path Helpers
# =============================================================================

"""Shorten absolute paths by replacing the home directory prefix with `~`."""
short_path(path::String) = let home = expanduser("~")
    startswith(path, home) ? "~" * path[length(home)+1:end] : path
end

"""
Paths under `anchor` → `relpath` from `anchor` (POSIX-style separators in the result).
Otherwise fall back to `short_path` (home as `~`).
"""
function display_path(path::AbstractString, anchor::AbstractString)::String
    ap = try
        abspath(expanduser(String(path)))
    catch
        return short_path(String(path))
    end
    an = try
        abspath(expanduser(String(anchor)))
    catch
        return short_path(String(path))
    end
    ap == an && return "."
    sep = Sys.iswindows() ? '\\' : '/'
    prefix = endswith(an, string(sep)) ? String(an) : an * sep
    if startswith(ap, prefix)
        return String(relpath(ap, an))
    end
    return short_path(String(path))
end

"""Read `name = "..."` from `proj_dir/Project.toml`; return `nothing` if missing or unreadable."""
function project_package_name(proj_dir::AbstractString)::Union{Nothing,String}
    path = joinpath(proj_dir, "Project.toml")
    isfile(path) || return nothing
    try
        m = match(r"name\s*=\s*\"([^\"]+)\"", read(path, String))
        m === nothing && return nothing
        cap = m.captures[1]
        return cap isa AbstractString ? String(cap) : nothing
    catch
        return nothing
    end
end

"""
Walk upward from `start_dir` to find the directory that should be passed to
`Pkg.activate` on workers.

If the first `Project.toml` found is the **vendored stub** (its `name` is
`SSHRunner`, matching this kit’s own `Project.toml`) and the parent
directory also has a `Project.toml`, skip it and keep walking so scripts
co-located with the kit inherit the application project root (regardless of
the kit folder’s basename).
"""
function resolve_pkg_project_dir(start_dir::AbstractString)::String
    test_dir = abspath(String(start_dir))
    fallback = dirname(test_dir)
    for _ in 1:24
        pt = joinpath(test_dir, "Project.toml")
        if isfile(pt)
            parent = dirname(test_dir)
            stub = project_package_name(test_dir)
            skip_stub = stub == "SSHRunner" && isfile(joinpath(parent, "Project.toml"))
            skip_stub || return test_dir
        end
        parent = dirname(test_dir)
        parent == test_dir && return fallback
        test_dir = parent
    end
    return fallback
end

"""
Default local project root for `runner.jl` / `setup.jl` / `suggest_workers.jl`.

- Standalone kit checkout (`Project.toml` at repo root): the kit directory.
- Embedded under a host app (`…/SSHRunner/` stub next to the app `Project.toml`): the app root.
"""
function runner_kit_project_root(kit_dir::AbstractString)::String
    root = String(abspath(expanduser(String(kit_dir))))
    if basename(root) == "src"
        root = dirname(root)
    end
    isfile(joinpath(root, "Project.toml")) || return dirname(root)
    parent = dirname(root)
    stub = project_package_name(root)
    if stub == "SSHRunner" && isfile(joinpath(parent, "Project.toml"))
        return parent
    end
    return root
end

# =============================================================================
# Output Formatting
# =============================================================================

const OUTPUT_WIDTH = 60

# -----------------------------------------------------------------------------
# Log File
# -----------------------------------------------------------------------------

const LOG_FILE_HANDLE = Ref{Union{IO,Nothing}}(nothing)

function write_both(msg::String; color::Symbol=:normal, bold::Bool=false)
    if color == :normal && !bold
        print(msg)
    else
        printstyled(msg; color=color, bold=bold)
    end
    if LOG_FILE_HANDLE[] !== nothing
        print(LOG_FILE_HANDLE[], msg)
        flush(LOG_FILE_HANDLE[])
    end
end

function writeln_both(msg::String=""; color::Symbol=:normal, bold::Bool=false)
    if color == :normal && !bold
        println(msg)
    else
        printstyled(msg * "\n"; color=color, bold=bold)
    end
    if LOG_FILE_HANDLE[] !== nothing
        println(LOG_FILE_HANDLE[], msg)
        flush(LOG_FILE_HANDLE[])
    end
end

function init_log_file(output_dir::String; prefix::String="runner", path_anchor::Union{Nothing,String}=nothing)
    isdir(output_dir) || mkpath(output_dir)
    timestamp = Dates.format(now(), dateformat"yyyy-mm-ddTHHMMSS")
    log_file = joinpath(output_dir, "$(prefix)_$(timestamp).log")
    LOG_FILE_HANDLE[] = open(log_file, "w")
    log_disp = path_anchor === nothing ? short_path(log_file) : display_path(log_file, path_anchor)
    writeln_both("Log file: $(log_disp)")
    return log_file
end

function close_log_file()
    if LOG_FILE_HANDLE[] !== nothing
        flush(LOG_FILE_HANDLE[])
        close(LOG_FILE_HANDLE[])
        LOG_FILE_HANDLE[] = nothing
    end
end

"""IO that writes to both primary (e.g. stdout) and secondary (e.g. log file).
For secondary: line-buffered — only complete lines are written. Progress bar
updates (\\r overwrites) are not written to log, avoiding bloat."""
mutable struct TeeIO{P<:IO,S<:Union{IO,Nothing}} <: IO
    primary::P
    secondary::S
    linebuf::Vector{UInt8}
end

function TeeIO(primary::IO, secondary::Union{IO,Nothing})
    TeeIO{typeof(primary),typeof(secondary)}(primary, secondary, UInt8[])
end

function Base.write(io::TeeIO, b::UInt8)
    write(io.primary, b)
    sec = io.secondary
    if sec isa IO
        if b == 0x0d          # \r — discard (progress-bar overwrite)
            empty!(io.linebuf)
        elseif b == 0x0a      # \n — flush complete line to log
            write(sec, io.linebuf)
            write(sec, b)
            flush(sec)
            empty!(io.linebuf)
        else
            push!(io.linebuf, b)
        end
    end
    return 1
end

function Base.write(io::TeeIO, b::AbstractVector{UInt8})
    return _teeio_write_bytes(io, b)
end

# `AbstractVector{UInt8}` alone is ambiguous with Base's `write(::IO, ::StridedArray)`
# for `Vector{UInt8}` / other strided inputs; this narrower method disambiguates.
function Base.write(io::TeeIO, b::StridedVector{UInt8})
    return _teeio_write_bytes(io, b)
end

function _teeio_write_bytes(io::TeeIO, b::AbstractVector{UInt8})
    write(io.primary, b)
    sec = io.secondary
    if sec isa IO
        for x in b
            if x == 0x0d
                empty!(io.linebuf)
            elseif x == 0x0a
                write(sec, io.linebuf)
                write(sec, x)
                flush(sec)
                empty!(io.linebuf)
            else
                push!(io.linebuf, x)
            end
        end
    end
    return length(b)
end

function Base.flush(io::TeeIO)
    flush(io.primary)
    sec = io.secondary
    if sec isa IO && !isempty(io.linebuf)
        write(sec, io.linebuf)
        flush(sec)
    end
    nothing
end

print_separator(; width::Int=OUTPUT_WIDTH) = writeln_both("="^width)
print_header(title::String) = (print_separator(); writeln_both(title); print_separator())

# -----------------------------------------------------------------------------
# Colored Output (disabled when NO_COLOR is set or stdout is not a TTY)
# -----------------------------------------------------------------------------

"""Whether to use ANSI colors (false when NO_COLOR is set or output is piped)."""
use_colors() = !haskey(ENV, "NO_COLOR") && stdout isa Base.TTY

function _print_colored(io, msg, color, bold=false)
    use_colors() ? printstyled(io, msg; color=color, bold=bold) : print(io, msg)
end

function print_ok(msg; io=stdout, bold=false)
    _print_colored(io, msg, :green, bold)
    if LOG_FILE_HANDLE[] !== nothing
        print(LOG_FILE_HANDLE[], msg); flush(LOG_FILE_HANDLE[])
    end
end

function print_err(msg; io=stdout, bold=false)
    _print_colored(io, msg, :red, bold)
    if LOG_FILE_HANDLE[] !== nothing
        print(LOG_FILE_HANDLE[], msg); flush(LOG_FILE_HANDLE[])
    end
end

function print_info(msg; io=stdout, bold=false)
    _print_colored(io, msg, :cyan, bold)
    if LOG_FILE_HANDLE[] !== nothing
        print(LOG_FILE_HANDLE[], msg); flush(LOG_FILE_HANDLE[])
    end
end

function print_warn(msg; io=stdout, bold=false)
    _print_colored(io, msg, :yellow, bold)
    if LOG_FILE_HANDLE[] !== nothing
        print(LOG_FILE_HANDLE[], msg); flush(LOG_FILE_HANDLE[])
    end
end

"""Setup-style: indent + symbol + message (used by setup.jl)."""
ok(msg)   = (write_both("  "); print_ok("✓ $msg");  writeln_both(""))
fail(msg) = (write_both("  "); print_err("✗ $msg"); writeln_both(""))
warn(msg) = (write_both("  "); print_warn("! $msg"); writeln_both(""))
