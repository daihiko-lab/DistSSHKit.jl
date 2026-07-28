# DistSSHKit.jl

[![CI](https://github.com/daihiko-lab/DistSSHKit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/daihiko-lab/DistSSHKit.jl/actions/workflows/CI.yml)
[![JETLS](https://github.com/daihiko-lab/DistSSHKit.jl/actions/workflows/jetls.yml/badge.svg)](https://github.com/daihiko-lab/DistSSHKit.jl/actions/workflows/jetls.yml)
[![codecov](https://codecov.io/gh/daihiko-lab/DistSSHKit.jl/graph/badge.svg?token=XWKRUL2DS1)](https://codecov.io/gh/daihiko-lab/DistSSHKit.jl)
[![Aqua QA](https://juliatesting.github.io/Aqua.jl/dev/assets/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Run any Julia script across local and SSH remote worker processes (Distributed.jl, not multi-threading). Built for a handful of SSH-reachable hosts with no job scheduler in front of them, covering clone, sync, run, and result collection end to end. Currently macOS only.

日本語: [README.ja.md](README.ja.md)

> [!IMPORTANT]
> **Under active development:** Interfaces may still change. For new use, pin the latest tag from [Releases](https://github.com/daihiko-lab/DistSSHKit.jl/releases) as `rev`. For now, the latest tag itself is moved forward to the newest commit; if you need exact reproducibility, pin a commit hash instead of the tag name.

If you use remote hosts, read [Using remote hosts](#using-remote-hosts) before the workflows below. For generative-AI use in this repo, see [Development with generative AI](#development-with-generative-ai).

Good fit for:

- Distributing code to a handful of SSH-reachable hosts with no Slurm or PBS in front of them
- Independent jobs you want to fan out across machines: parameter sweeps, Monte Carlo runs, batches over multiple conditions
- Making sure every host runs the exact same Julia project (same git commit)
- Not wanting to manually gather logs and result files from each machine afterward

Not a fit for large-scale HPC cluster operation, multi-threaded parallelism, or dynamic scaling. See the sections below for actual usage.

## Install and run

Recommended: add the kit as a normal Julia package via `Pkg.add`, then call it via `julia -m DistSSHKit` (Julia 1.12+). Run from your app root (directory with `Project.toml`).

```bash
cd MyProject.jl

# Once: pin a version (rev is a tag name)
julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/daihiko-lab/DistSSHKit.jl.git", rev="vX.Y.Z")'
```

See [Releases](https://github.com/daihiko-lab/DistSSHKit.jl/releases) for the tag to pin.

Try it locally first (no SSH needed) — copy the bundled demos into your project, then run one:

```bash
julia --project=. -m DistSSHKit demo install
julia --project=. -m DistSSHKit runner --local 2 demos/param_sweep.jl
julia --project=. -m DistSSHKit runner --local 2 demos/coin_flip.jl
```

`demo install` copies each demo as a single, self-contained file into `./demos/` — open and edit `demos/*.jl` directly in your editor. Existing files are not overwritten (use `--force` to reset to the bundled version).

Notes:
- To see the bundled paths without copying: `julia --project=. -m DistSSHKit demo list`
- To pick the destination explicitly: `julia --project=. -m DistSSHKit demo install --dest DIR`

With remote hosts, the flow looks like this:

```bash
# Remote setup (first time)
julia --project=. -m DistSSHKit setup --clone HOST1 HOST2 ...
julia --project=. -m DistSSHKit setup --instantiate HOST1 HOST2 ...

# Sync code
julia --project=. -m DistSSHKit setup --sync HOST1 HOST2 ...

# Distributed run
julia --project=. -m DistSSHKit runner \
  --local N HOST1:W HOST2:W ... scripts/jobs.jl [args...]

# Worker-count hints
julia --project=. -m DistSSHKit suggest-workers --local HOST1 HOST2
```

Everything after `runner` / `demo` / `setup` / `suggest-workers` becomes that command's `ARGS`. If the worker module name differs from your `Project.toml` `name`, use `--package NAME`.

See each subcommand's full option list with `--help`:

```bash
julia --project=. -m DistSSHKit runner --help
julia --project=. -m DistSSHKit demo --help
julia --project=. -m DistSSHKit setup --help
julia --project=. -m DistSSHKit suggest-workers --help
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

Runnable examples: [`demos/`](demos/) (parameter sweep, coin flips). To copy one into your own project to read and edit, use `demo install` (see [Install and run](#install-and-run)).

`runner()` runs `using Distributed` before it `include`s your script, so you don't need `using Distributed` yourself just to call `pmap`, etc. (worth adding anyway if you also run or test the script standalone).

## Using remote hosts

Skip this section entirely if you only use `--local N`. To run across multiple remote hosts, set the following up first. Developed and tested on macOS only (other OSes are not validated). Each host needs Julia 1.12+; your local machine needs Git, OpenSSH (`ssh`), and rsync.

DistSSHKit connects to remotes using your normal `ssh` command. Worker startup and result collection all go through that connection. You must be able to log in **without typing a password** (set up key auth, e.g. `ssh-copy-id`). Check each host with:

```bash
ssh HOST echo ok
```

When calling `runner`, pass hosts as `host` or `host:N` (`N` = workers on that host). Example: `runner host1:10 host2:8 script.jl`

To override SSH behavior, set `DISTRIBUTED_SSH_OPTS` (if unset, defaults apply: non-interactive login, 10s connect timeout, accept new host keys on first connect, keepalives enabled):

```bash
export DISTRIBUTED_SSH_OPTS="-o ProxyJump=bastion ..."
```

Each remote host needs Julia installed (auto-detected unless you pass `--julia PATH` or `JULIA_DISTRIBUTED_EXE`). For `setup --clone` / `--sync`, each host must reach `origin` over SSH (clone/pull). At run time, `runner` automatically checks that all hosts are on the same git commit, and warns if your local working tree has uncommitted changes (both checks are skipped with `--skip-hash-check`). `setup --check` additionally verifies that each host's Julia version matches yours (a major.minor mismatch fails the check; pass `--ignore-julia-version` to downgrade that to a warning; a patch-only difference always just warns).

Path-related variables you'll likely need:

- **Local project root**: directory where you run `julia --project=.`; override with `DISTRIBUTED_PROJECT_ROOT`
- **Remote repo root**: `DISTRIBUTED_REMOTE_PROJECT_ROOT` or `setup --remote-path` (default `~/parent/repo-name`)
- **Script output**: `ENV["DISTRIBUTED_OUTPUT_DIR"]`, set in `init_output_dir!`
- **Dirs to rsync after a run**: `DISTRIBUTED_COLLECT_DIRS` (colon-separated)

Check everything is ready:

```bash
cd ~/GitHub/MyProject.jl
julia --project=. -m DistSSHKit setup --check host1 host2
```

First-time setup, in this order:

```bash
# 1. git clone the repo onto each host
julia --project=. -m DistSSHKit setup --clone HOST ...

# 2. Pkg.instantiate on each host to install dependencies
julia --project=. -m DistSSHKit setup --instantiate HOST ...

# 3. Verify clone, dependencies, Julia availability, etc.
julia --project=. -m DistSSHKit setup --check HOST ...

# 4. Align each host to your local git commit (also used before every run)
julia --project=. -m DistSSHKit setup --sync HOST ...
```

For quick manual iteration before you're ready to commit, `setup --rsync HOST ...` copies the local tree via rsync instead — but it bypasses git entirely (no commit, no hash verification), so `runner`'s git checks will likely warn/fail against it unless you pass `--skip-hash-check`. Prefer `--sync` whenever you want the git-commit reproducibility guarantee.

### Recommended workflow: iterate vs. production runs

- **Iterating** (still editing your script): `setup --rsync` + `runner --skip-hash-check` is fine. Faster feedback loop; git parity isn't the point yet.
- **Before a production run**: commit, then `setup --sync HOST ...` followed by `setup --check HOST ...` with no warnings left. Don't run with `--skip-hash-check` for a run you intend to keep. `setup --check` only fails on a major.minor mismatch — a patch-only difference (e.g. 1.12.6 vs 1.12.9) just warns — so before a result you plan to keep or publish, pin all hosts to the same patch (e.g. `juliaup default 1.12.6`) and confirm the check comes back clean.
- **Recording results**: keep the `runner` log (`results/runner_*.log`) alongside your output — it already records the exact subcommand args and a best-effort snapshot of the Julia environment (see log header).

## Troubleshooting

- **Git hash mismatch**: `julia -m DistSSHKit setup --sync ...`
- **`attempt to send to unknown socket`**: `DISTRIBUTED_INIT_DELAY_SEC=10`
- **Julia not found on remote**: `--julia PATH` or `JULIA_DISTRIBUTED_EXE`
- **Anything else**: `--help` on each subcommand; [Using remote hosts](#using-remote-hosts)

## For developers

If you want to edit the kit's own code, or need the checklist to run before opening a PR, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Development with generative AI

This is still early-stage development, so maintainer review and understanding have not fully caught up everywhere. Correctness in practice will be validated through use in other projects and research.

The Julia community discusses the line between unreviewed vibe-coding and human-understood AI-assisted work (e.g. [Discourse thread](https://discourse.julialang.org/t/should-general-have-a-guideline-or-rule-preventing-registration-of-vibe-coded-packages/133205), [General policy](https://github.com/JuliaRegistries/General/blob/master/README.md)). This repository takes those discussions as reference.

## License

MIT. See [`LICENSE`](LICENSE).
