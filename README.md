# ParallelRunnerKit.jl

[![CI](https://github.com/daihiko-lab/ParallelRunnerKit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/daihiko-lab/ParallelRunnerKit.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/daihiko-lab/ParallelRunnerKit.jl/graph/badge.svg)](https://codecov.io/gh/daihiko-lab/ParallelRunnerKit.jl)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Run any Julia driver script across local and SSH remote worker processes (Distributed.jl, not multi-threading). Built for a handful to a dozen SSH-reachable hosts with no job scheduler in front of them, covering clone, sync, run, and result collection end to end.

日本語: [README.ja.md](README.ja.md)

**Status:** Pre-1.0 (`0.x`); interfaces may still change between minor versions.

If you use remote hosts, read [Environment & SSH](#environment--ssh) before the workflows below. For generative-AI use in this repo, see [Development with generative AI](#development-with-generative-ai).

## Two workflows only

1. Package app (experimental): [Pkg Apps](https://pkgdocs.julialang.org/v1/apps/) for `prunner` / `psetup` / `psuggest`. Kit is not vendored in your repo. [Steps](#1-package-app-install-experimental)
2. CLI (recommended): run `runner.jl`, etc. with `julia --project=.` from a clone/submodule. [Steps](#2-cli-scripts)

Run either one from your app root (directory with `Project.toml`).

## Shared: your driver script

The Julia script you distribute must define exactly these two functions in `Main` (same for 1 and 2):

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

Runnable minimal example: [`templates/script_template.jl`](templates/script_template.jl).

`runner.jl` runs `using Distributed` before it `include`s your script, so you don't need `using Distributed` yourself just to call `pmap`, etc. (worth adding anyway if you also run or test the script standalone).

## 1. Package app install (experimental)

> Experimental: Julia 1.12 [Pkg Apps](https://pkgdocs.julialang.org/v1/apps/) is still experimental. Install `ParallelRunnerKit` as a package and register `prunner` / `psetup` / `psuggest` under `~/.julia/bin`. Unlike option 2, you do not vendor the kit in your app repository.

### Install (once)

```bash
# Local development
julia -e 'using Pkg; Pkg.Apps.develop(path="/path/to/ParallelRunnerKit.jl")'

# From a released commit
# julia -e 'using Pkg; Pkg.Apps.add(url="https://github.com/daihiko-lab/ParallelRunnerKit.jl.git")'

export PATH="$HOME/.julia/bin:$PATH"   # persist in .zshrc, etc.
prunner --help
```

| Command | Option 2 script | Purpose |
|---------|-----------------|---------|
| `prunner` | `runner.jl` | Distributed runs |
| `psetup` | `setup.jl` | clone / sync / cleanup |
| `psuggest` | `suggest_workers.jl` | Worker-count hints |

### Examples

`cd` into `MyApp.jl/`, not into a clone of this kit repo:

```bash
cd ~/projects/MyApp.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'

psetup --clone HOST1 HOST2 ...
psetup --instantiate HOST1 HOST2 ...
psetup --sync HOST1 HOST2 ...
prunner --local N HOST1:W HOST2:W ... scripts/jobs.jl [args...]
psuggest --local HOST1 HOST2
```

- No `julia --project=.` wrapper; the current directory is the project root.
- For another path: `export DISTRIBUTED_PROJECT_ROOT=/path/to/MyApp.jl`.

## 2. CLI (scripts)

Call `runner.jl`, `setup.jl`, and `suggest_workers.jl` with `julia --project=.`. The `.jl` files must be reachable from your project (clone or submodule). Recommended for stable use.

### 2-a. In your application (typical)

```bash
cd MyApp.jl
git submodule add https://github.com/daihiko-lab/ParallelRunnerKit.jl.git ParallelRunnerKit
julia --project=. -e 'using Pkg; Pkg.develop(path="ParallelRunnerKit")'
```

`Pkg.develop(path=...)` registers `ParallelRunnerKit` in `MyApp.jl/Project.toml` as `[deps]` + `[sources]`, and resolves the kit's own dependencies (`ArgParse`, `JSON3`, etc.) automatically. No manual `[deps]` copying needed (`Distributed` / `Dates` are stdlib, so they aren't required either).

Stay in `MyApp.jl/`, then:

```bash
# Remote setup (first time)
julia --project=. ParallelRunnerKit/src/setup.jl --clone HOST1 HOST2 ...
julia --project=. ParallelRunnerKit/src/setup.jl --instantiate HOST1 HOST2 ...

# Sync code
julia --project=. ParallelRunnerKit/src/setup.jl --sync HOST1 HOST2 ...

# Distributed run
julia --project=. ParallelRunnerKit/src/runner.jl --local N HOST1:W HOST2:W ... scripts/jobs.jl [args...]

# Worker-count hints
julia --project=. ParallelRunnerKit/src/suggest_workers.jl --local HOST1 HOST2
```

- Paths use the `ParallelRunnerKit/src/` prefix (adjust if your submodule path differs).
- If the worker module name differs from your `Project.toml` `name`, use `--package NAME`.

### 2-b. This repository standalone

For developing or smoke-testing the kit itself. Use `src/` paths (no `ParallelRunnerKit/` prefix).

```bash
git clone https://github.com/daihiko-lab/ParallelRunnerKit.jl.git
cd ParallelRunnerKit.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'

julia --project=. src/runner.jl --local 2 templates/script_template.jl
julia --project=. src/setup.jl --help
```

Help:

```bash
julia --project=. ParallelRunnerKit/src/runner.jl --help    # 2-a
julia --project=. src/runner.jl --help                      # 2-b
```

## Environment & SSH

When using remote hosts (1 or 2), set these up first.

- 1 (package app): `psetup --check HOST ...`
- 2 (scripts): `julia --project=. ParallelRunnerKit/src/setup.jl --check HOST ...`

### Tested platform

- Developed and tested on macOS only (other OSes are not validated)
- Julia 1.12+ on local and every remote host
- Local machine needs Git, OpenSSH (`ssh`), and rsync

### SSH requirements

| Item | Requirement |
|------|-------------|
| Auth | Public-key only (no password prompts); `BatchMode=yes` non-interactive login |
| Smoke test | `ssh HOST echo ok` on every host |
| Host args | `host` or `host:N` (worker count) |
| Custom options | `export DISTRIBUTED_SSH_OPTS="-o Foo=bar ..."` |

Default SSH options when `DISTRIBUTED_SSH_OPTS` is unset: `BatchMode=yes`, `ConnectTimeout=10`, `StrictHostKeyChecking=accept-new`, keepalives.

### Remote hosts must have

| Item | Requirement |
|------|-------------|
| Julia | Installed; auto-detected or `--julia PATH` / `JULIA_DISTRIBUTED_EXE` |
| Git | For `--clone` / `--sync`, SSH access to `origin` from each host |
| Repo state | Same git commit on all machines (checked by runner) |

### Path layout

| Role | Variable / option | Meaning |
|------|-------------------|---------|
| Local project root | 1: `pwd()` or `DISTRIBUTED_PROJECT_ROOT` / 2: `julia --project=.` dir | App `Project.toml` location |
| Remote repo root | `DISTRIBUTED_REMOTE_PROJECT_ROOT` or `setup --remote-path` | Absolute path on SSH host; default `~/parent/repo-name` |
| Driver output | `ENV["DISTRIBUTED_OUTPUT_DIR"]` | Set in `init_output_dir!` |
| Post-run rsync dirs | `DISTRIBUTED_COLLECT_DIRS` | Colon-separated |

```bash
cd ~/GitHub/MyApp.jl
psetup --check host1 host2                                           # 1
# julia --project=. ParallelRunnerKit/src/setup.jl --check host1 host2  # 2
```

### First-time remote setup

```bash
# 1 (package app)
psetup --clone HOST ...
psetup --instantiate HOST ...
psetup --check HOST ...
psetup --sync HOST ...

# 2 (script CLI): replace psetup with ParallelRunnerKit/src/setup.jl
```

Local workers only (`--local N`): SSH and remote paths not required.

## Troubleshooting

| Problem | Try |
|---------|-----|
| Git hash mismatch | 1: `psetup --sync` / 2: `setup.jl --sync` |
| `attempt to send to unknown socket` | `DISTRIBUTED_INIT_DELAY_SEC=10` |
| Julia not found on remote | `--julia PATH` or `JULIA_DISTRIBUTED_EXE` |
| Anything else | `--help` on each command; [Environment & SSH](#environment--ssh) |

## Development

### How to get it

`git clone` / submodule, or `Pkg.add(url=...)` / `Pkg.Apps.add(url=...)`. General Registry registration is not planned right now (we'd be happy if that becomes possible someday…).

### Development with generative AI

At this stage the project is closer to vibe-coding. Most code and docs are written with LLM help (e.g. Cursor), and maintainer review/understanding has not fully caught up everywhere. For a public `0.x` GitHub repo, we operate on that premise. Correctness in practice will be validated through use in other projects and research.

The Julia community discusses the line between unreviewed vibe-coding and human-understood AI-assisted work (e.g. [Discourse thread](https://discourse.julialang.org/t/should-general-have-a-guideline-or-rule-preventing-registration-of-vibe-coded-packages/133205), [General policy](https://github.com/JuliaRegistries/General/blob/master/README.md)). This repository takes those discussions as reference.

## License

MIT. See [`LICENSE`](LICENSE).
