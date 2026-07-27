# SSHRunner.jl

[![CI](https://github.com/daihiko-lab/SSHRunner.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/daihiko-lab/SSHRunner.jl/actions/workflows/CI.yml)
[![JETLS](https://github.com/daihiko-lab/SSHRunner.jl/actions/workflows/jetls.yml/badge.svg)](https://github.com/daihiko-lab/SSHRunner.jl/actions/workflows/jetls.yml)
[![codecov](https://codecov.io/gh/daihiko-lab/SSHRunner.jl/graph/badge.svg)](https://codecov.io/gh/daihiko-lab/SSHRunner.jl)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Run any Julia script across local and SSH remote worker processes (Distributed.jl, not multi-threading). Built for a handful of SSH-reachable hosts with no job scheduler in front of them, covering clone, sync, run, and result collection end to end.

日本語: [README.ja.md](README.ja.md)

**Status:** Pre-1.0 (`0.x`); interfaces may still change between minor versions.

If you use remote hosts, read [Using remote hosts](#using-remote-hosts) before the workflows below. For generative-AI use in this repo, see [Development with generative AI](#development-with-generative-ai).

Good fit for:

- Distributing code to a handful of SSH-reachable hosts with no Slurm or PBS in front of them
- Independent jobs you want to fan out across machines: parameter sweeps, Monte Carlo runs, batches over multiple conditions
- Making sure every host runs the exact same Julia project (same git commit)
- Not wanting to manually gather logs and result files from each machine afterward

Not a fit for large-scale HPC cluster operation, multi-threaded parallelism, or dynamic scaling. See the sections below for actual usage.

## Install and run

Recommended: add the kit as a normal Julia package via `Pkg.add`, then call it via `julia -m SSHRunner` (Julia 1.12+). Run from your app root (directory with `Project.toml`).

```bash
cd MyProject.jl

# Once: pin a version (rev is a tag name)
julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/daihiko-lab/SSHRunner.jl.git", rev="vX.Y.Z")'
```

See [Releases/Tags](https://github.com/daihiko-lab/SSHRunner.jl/tags) for the latest tag name.

Try it locally first (no SSH needed) — copy the bundled demos into your project, then run one:

```bash
julia --project=. -m SSHRunner demo install
julia --project=. -m SSHRunner runner --local 2 demos/param_sweep.jl
julia --project=. -m SSHRunner runner --local 2 demos/coin_flip.jl
```

`demo install` copies each demo as a single, self-contained file into `./demos/` — open and edit `demos/*.jl` directly in your editor. Existing files are not overwritten (use `--force` to reset to the bundled version).

Notes:
- To see the bundled paths without copying: `julia --project=. -m SSHRunner demo list`
- To pick the destination explicitly: `julia --project=. -m SSHRunner demo install --dest DIR`

With remote hosts, the flow looks like this:

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

Everything after `runner` / `demo` / `setup` / `suggest-workers` becomes that command's `ARGS`. If the worker module name differs from your `Project.toml` `name`, use `--package NAME`.

See each subcommand's full option list with `--help`:

```bash
julia --project=. -m SSHRunner runner --help
julia --project=. -m SSHRunner demo --help
julia --project=. -m SSHRunner setup --help
julia --project=. -m SSHRunner suggest-workers --help
```

`Pkg.add(url=..., rev=...)` registers `[deps]` + `[sources]` in `Project.toml`, and records the actual commit fetched in `Manifest.toml`. These two files are the source of truth for the version (no submodule needed). To update, change `rev` and re-run `Pkg.add`.

## Writing the script you run

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

Runnable examples: [`demos/`](demos/) (parameter sweep, coin flips).

`runner()` runs `using Distributed` before it `include`s your script, so you don't need `using Distributed` yourself just to call `pmap`, etc. (worth adding anyway if you also run or test the script standalone).

## Using remote hosts

Skip this section entirely if you only use `--local N`. To run across multiple remote hosts, set the following up first. Developed and tested on macOS only (other OSes are not validated). Each host needs Julia 1.12+; your local machine needs Git, OpenSSH (`ssh`), and rsync.

SSHRunner connects to remotes using your normal `ssh` command. Worker startup and result collection all go through that connection. You must be able to log in **without typing a password** (set up key auth, e.g. `ssh-copy-id`). Check each host with:

```bash
ssh HOST echo ok
```

When calling `runner`, pass hosts as `host` or `host:N` (`N` = workers on that host). Example: `runner host1:10 host2:8 script.jl`

To override SSH behavior, set `DISTRIBUTED_SSH_OPTS` (if unset, defaults apply: non-interactive login, 10s connect timeout, accept new host keys on first connect, keepalives enabled):

```bash
export DISTRIBUTED_SSH_OPTS="-o ProxyJump=bastion ..."
```

Each remote host needs Julia installed (auto-detected unless you pass `--julia PATH` or `JULIA_DISTRIBUTED_EXE`). For `setup --clone` / `--sync`, each host must reach `origin` over SSH (clone/pull). At run time, `runner` automatically checks that all hosts are on the same git commit.

Path-related variables you'll likely need:

- **Local project root**: directory where you run `julia --project=.`; override with `DISTRIBUTED_PROJECT_ROOT`
- **Remote repo root**: `DISTRIBUTED_REMOTE_PROJECT_ROOT` or `setup --remote-path` (default `~/parent/repo-name`)
- **Script output**: `ENV["DISTRIBUTED_OUTPUT_DIR"]`, set in `init_output_dir!`
- **Dirs to rsync after a run**: `DISTRIBUTED_COLLECT_DIRS` (colon-separated)

Check everything is ready:

```bash
cd ~/GitHub/MyProject.jl
julia --project=. -m SSHRunner setup --check host1 host2
```

First-time setup, in this order:

```bash
# 1. git clone the repo onto each host
julia --project=. -m SSHRunner setup --clone HOST ...

# 2. Pkg.instantiate on each host to install dependencies
julia --project=. -m SSHRunner setup --instantiate HOST ...

# 3. Verify clone, dependencies, Julia availability, etc.
julia --project=. -m SSHRunner setup --check HOST ...

# 4. Align each host to your local git commit (also used before every run)
julia --project=. -m SSHRunner setup --sync HOST ...
```

## Troubleshooting

- **Git hash mismatch**: `julia -m SSHRunner setup --sync ...`
- **`attempt to send to unknown socket`**: `DISTRIBUTED_INIT_DELAY_SEC=10`
- **Julia not found on remote**: `--julia PATH` or `JULIA_DISTRIBUTED_EXE`
- **Anything else**: `--help` on each subcommand; [Using remote hosts](#using-remote-hosts)

## For kit developers: develop via `Pkg.develop`

If you're editing the kit's own code while testing it (not needed for regular use), clone it anywhere and point `Pkg.develop` at that path:

```bash
git clone https://github.com/daihiko-lab/SSHRunner.jl.git ~/dev/SSHRunner.jl
cd MyProject.jl
julia --project=. -e 'using Pkg; Pkg.develop(path=expanduser("~/dev/SSHRunner.jl"))'
```

Same call interface as `Pkg.add` (`julia -m SSHRunner runner ...`, etc.). Edits in that checkout take effect immediately.

### Local verification

From the kit checkout root, maintainers typically run:

```bash
# 1. Tests (unit, runner smoke, demo scripts, log output, ...)
julia --project=. -e 'using Pkg; Pkg.test()'

# 2. Static analysis — needs `jetls` on PATH (e.g. Pkg.Apps.add + `export PATH="$HOME/.julia/bin:$PATH"` in shell rc)
jetls check demos/*.jl src/SSHRunner.jl src/runner.jl src/setup.jl src/suggest_workers.jl test/*.jl test/fixtures/*.jl

# 3. Manual smoke (same as README quickstart)
julia --project=. -m SSHRunner runner --local 2 demos/param_sweep.jl
julia --project=. -m SSHRunner runner --local 2 demos/coin_flip.jl
```

`Pkg.test()` covers both the demo scripts (`test/test_demos.jl`) and `demo install`/`demo list` (`test/test_demo_cli.jl`) automatically; steps 2–3 are extra checks before pushing.

CI also runs [`.github/workflows/CI.yml`](.github/workflows/CI.yml) and [`.github/workflows/jetls.yml`](.github/workflows/jetls.yml).

`Pkg.add(url=..., rev=...)` and `Pkg.develop(path=...)` both make you explicitly choose the version's source of truth, unlike General Registry's automatic `[compat]`-driven resolution. That's a deliberate fit for research use (pin an exact commit, keep it reproducible), not just a missing feature — General registration may be worth revisiting once the `0.x` interface settles, mainly for discoverability.

## Development with generative AI

At this stage, maintainer review and understanding have not fully caught up everywhere. For a public `0.x` GitHub repo, we operate on that premise. Correctness in practice will be validated through use in other projects and research.

The Julia community discusses the line between unreviewed vibe-coding and human-understood AI-assisted work (e.g. [Discourse thread](https://discourse.julialang.org/t/should-general-have-a-guideline-or-rule-preventing-registration-of-vibe-coded-packages/133205), [General policy](https://github.com/JuliaRegistries/General/blob/master/README.md)). This repository takes those discussions as reference.

## License

MIT. See [`LICENSE`](LICENSE).
