# ParallelRunnerKit.jl

[![CI](https://github.com/daihiko-lab/ParallelRunnerKit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/daihiko-lab/ParallelRunnerKit.jl/actions/workflows/CI.yml)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Run any Julia driver script across local and SSH remote worker **processes** (Distributed.jl, not multi-threading).

日本語: [README.ja.md](README.ja.md)

**Status:** Pre-1.0 (`0.x`); interfaces may still change between minor versions.

## Install

```bash
git clone https://github.com/daihiko-lab/ParallelRunnerKit.jl.git
cd ParallelRunnerKit.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Or vendor it into another app (submodule, subtree, or plain copy) — see [Embedding](#embedding) below.

## Your driver script

A script run via `runner.jl` defines exactly two functions in `Main`:

```julia
# Called BEFORE workers are added. Must set ENV["DISTRIBUTED_OUTPUT_DIR"].
function init_output_dir!(args::Vector{String})::String
    ...
end

# Called AFTER workers are ready. Use nworkers()/workers() with pmap, etc.
function main()
    ...
end
```

See [`templates/script_template.jl`](templates/script_template.jl) for a runnable minimal example.

## Quick start

```bash
# 1. Clone + install deps on remotes (first time only)
julia --project=. setup.jl --clone HOST1 HOST2 ...
julia --project=. setup.jl --instantiate HOST1 HOST2 ...

# 2. Sync code after local commits
julia --project=. setup.jl --sync HOST1 HOST2 ...

# 3. Run: N local workers + W workers per remote host
julia --project=. runner.jl --local N HOST1:W HOST2:W ... path/to/script.jl [args...]
```

Try the template:

```bash
julia --project=. runner.jl --local 2 templates/script_template.jl
```

Full options and environment variables:

```bash
julia --project=. runner.jl --help
julia --project=. setup.jl --help
julia --project=. suggest_workers.jl --help
```

## Prerequisites

- macOS (developed and tested here; other platforms are not validated)
- SSH key auth to remote hosts, with Git and Julia installed there
- Same repo path on all machines (or set `--remote-path` / `DISTRIBUTED_REMOTE_PROJECT_ROOT`)

## Embedding

```bash
git submodule add https://github.com/daihiko-lab/ParallelRunnerKit.jl.git ParallelRunnerKit
```

Merge this repo's `[deps]` into your host `Project.toml`, prefix script paths with `ParallelRunnerKit/` (e.g. `ParallelRunnerKit/runner.jl`), and implement `init_output_dir!` / `main()` as above. If the worker module name differs from your `Project.toml` `name`, use `runner.jl --package NAME`.

## Troubleshooting

| Problem | Try |
|---------|-----|
| Git hash mismatch across hosts | `setup.jl --sync` or `--pull` |
| Julia not found on remote | `--julia PATH` or `JULIA_DISTRIBUTED_EXE` |
| Stale worker processes | `setup.jl --cleanup` |
| `attempt to send to unknown socket` | `DISTRIBUTED_INIT_DELAY_SEC=10` |

## License

MIT — see [`LICENSE`](LICENSE)
