# SSHRunner.jl

[![CI](https://github.com/daihiko-lab/SSHRunner.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/daihiko-lab/SSHRunner.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/daihiko-lab/SSHRunner.jl/graph/badge.svg)](https://codecov.io/gh/daihiko-lab/SSHRunner.jl)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Run any Julia driver script across local and SSH remote worker processes (Distributed.jl, not multi-threading). Built for a handful to a dozen SSH-reachable hosts with no job scheduler in front of them, covering clone, sync, run, and result collection end to end.

日本語: [README.ja.md](README.ja.md)

**Status:** Pre-1.0 (`0.x`); interfaces may still change between minor versions.

If you use remote hosts, read [Environment & SSH](#environment--ssh) before the workflows below. For generative-AI use in this repo, see [Development with generative AI](#development-with-generative-ai).

## Install and run

Recommended: add the kit as a normal Julia package via `Pkg.add`, then call it via `julia -m SSHRunner` (Julia 1.12+; no Pkg Apps install needed). Run from your app root (directory with `Project.toml`).

```bash
cd MyProject.jl

# Once: pin a version (rev is a tag name)
julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/daihiko-lab/SSHRunner.jl.git", rev="vX.Y.Z")'
```

See [Releases/Tags](https://github.com/daihiko-lab/SSHRunner.jl/tags) for the latest tag name.

```bash
# Remote setup (first time)
julia --project=. -m SSHRunner setup --clone HOST1 HOST2 ...
julia --project=. -m SSHRunner setup --instantiate HOST1 HOST2 ...

# Sync code
julia --project=. -m SSHRunner setup --sync HOST1 HOST2 ...

# Distributed run
julia --project=. -m SSHRunner runner \
  --local N HOST1:W HOST2:W ... scripts/jobs.jl [args...]

# Worker-count hints
julia --project=. -m SSHRunner suggest-workers --local HOST1 HOST2
```

Everything after `runner` / `setup` / `suggest-workers` becomes that command's `ARGS`. If the worker module name differs from your `Project.toml` `name`, use `--package NAME`.

`Pkg.add(url=..., rev=...)` registers `[deps]` + `[sources]` in `Project.toml`, and records the actual commit fetched in `Manifest.toml`. These two files are the source of truth for the version (no submodule needed). To update, change `rev` and re-run `Pkg.add`.

## Shared: your driver script

The Julia script you distribute must define exactly these two functions in `Main`:

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

`runner()` runs `using Distributed` before it `include`s your script, so you don't need `using Distributed` yourself just to call `pmap`, etc. (worth adding anyway if you also run or test the script standalone).

## Environment & SSH

When using remote hosts, set these up first. Check with `setup()` (or `src/setup.jl --check HOST ...`).

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
| Local project root | `julia --project=.` dir, or `DISTRIBUTED_PROJECT_ROOT` | App `Project.toml` location |
| Remote repo root | `DISTRIBUTED_REMOTE_PROJECT_ROOT` or `setup --remote-path` | Absolute path on SSH host; default `~/parent/repo-name` |
| Driver output | `ENV["DISTRIBUTED_OUTPUT_DIR"]` | Set in `init_output_dir!` |
| Post-run rsync dirs | `DISTRIBUTED_COLLECT_DIRS` | Colon-separated |

```bash
cd ~/GitHub/MyProject.jl
julia --project=. -m SSHRunner setup --check host1 host2
```

### First-time remote setup

```bash
julia --project=. -m SSHRunner setup --clone HOST ...
julia --project=. -m SSHRunner setup --instantiate HOST ...
julia --project=. -m SSHRunner setup --check HOST ...
julia --project=. -m SSHRunner setup --sync HOST ...
```

Local workers only (`--local N`): SSH and remote paths not required.

## Troubleshooting

| Problem | Try |
|---------|-----|
| Git hash mismatch | `julia -m SSHRunner setup --sync ...` |
| `attempt to send to unknown socket` | `DISTRIBUTED_INIT_DELAY_SEC=10` |
| Julia not found on remote | `--julia PATH` or `JULIA_DISTRIBUTED_EXE` |
| Anything else | `--help` on each subcommand; [Environment & SSH](#environment--ssh) |

## For kit developers: develop via submodule

If you're editing the kit's own code while testing it (not needed for regular use):

```bash
cd MyProject.jl
git submodule add https://github.com/daihiko-lab/SSHRunner.jl.git SSHRunner
julia --project=. -e 'using Pkg; Pkg.develop(path="SSHRunner")'
```

Same call interface as `Pkg.add` (`julia -m SSHRunner runner ...`, etc.). Edits inside the submodule take effect immediately. The submodule's commit is the source of truth for the version.

This and `Pkg.add(url=..., rev=...)` both make you explicitly choose the version's source of truth, unlike General Registry's automatic `[compat]`-driven resolution. Registration itself is not planned right now (we'd be happy if that becomes possible someday…).

## Development with generative AI

At this stage the project is closer to vibe-coding. Most code and docs are written with LLM help (e.g. Cursor), and maintainer review/understanding has not fully caught up everywhere. For a public `0.x` GitHub repo, we operate on that premise. Correctness in practice will be validated through use in other projects and research.

The Julia community discusses the line between unreviewed vibe-coding and human-understood AI-assisted work (e.g. [Discourse thread](https://discourse.julialang.org/t/should-general-have-a-guideline-or-rule-preventing-registration-of-vibe-coded-packages/133205), [General policy](https://github.com/JuliaRegistries/General/blob/master/README.md)). This repository takes those discussions as reference.

## License

MIT. See [`LICENSE`](LICENSE).
