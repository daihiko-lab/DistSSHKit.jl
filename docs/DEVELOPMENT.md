# Developer Notes for `ParallelRunnerKit/`

Design notes for eventually extracting `ParallelRunnerKit/` into a reusable
package (working name: `DistributedRunner.jl`). For developers only — usage
docs live in [README.md](../README.md).

日本語: [DEVELOPMENT.ja.md](DEVELOPMENT.ja.md)

**Platform:** Developed and tested on **macOS only**; non-macOS behaviour is not validated.

**Distribution split:**
- **Distributed runs only:** copy `ParallelRunnerKit/` wholesale, satisfy the script contract (`init_output_dir!`, `main()`), merge its `Project.toml` `[deps]` into your environment. Use `--package NAME` if the worker module name differs from the root `Project.toml` `name`.
- **Simulation only:** delete `ParallelRunnerKit/` entirely; nothing else references it by name.

**Folder name:** should stay `ParallelRunnerKit` to match the module / stub `Project.toml` name. Upstream: **[daihiko-lab/ParallelRunnerKit.jl](https://github.com/daihiko-lab/ParallelRunnerKit.jl)**. `resolve_pkg_project_dir` keys off `name == "ParallelRunnerKit"`, not the directory basename.

## Vendoring into a host application

**As a git submodule:**

```bash
git clone --recurse-submodules <parent-repo-url>
# or, if already cloned without submodules:
git submodule update --init --recursive
```

Bump the pinned commit after pushing here: `cd ParallelRunnerKit && git pull origin main && cd .. && git add ParallelRunnerKit && git commit -m "Bump ParallelRunnerKit submodule"`.

**As a one-off mirror (no submodule):** from the host app's root, `git subtree split -P ParallelRunnerKit -b publish-branch`, then push that branch to this repo's `main`. Use `--force-with-lease` only when intentionally rewriting `main` here.

## Coupling to the host application

| Location | What it assumes |
|----------|-----------------|
| `runner.jl` | Loads the project's package on workers via `Project.toml` `name` (or `--package`); calls `init_output_dir!(ARGS)` then `main()` on the included script |
| `src/ParallelRunnerKit.jl` | Shared helpers (paths, logging, SSH/git, CLI parsing, memory/git parity checks); no host package imports |
| `setup.jl` | Project root is a Julia project with a `Project.toml` |

No file imports the host application by name — the runner discovers the package name from `Project.toml`, so it works unmodified on any Julia project.

## Interface contract (script side)

A script run via `runner.jl` must expose exactly two functions in `Main`:

```julia
# Called BEFORE workers are added. Must set ENV["DISTRIBUTED_OUTPUT_DIR"].
# Optionally set ENV["DISTRIBUTED_SKIP_COLLECT"] = "1" if results are
# saved only on the master.
function init_output_dir!(args::Vector{String})::String
    ...
end

# Called AFTER workers are ready. Use nworkers()/workers() and pick your
# own parallelism strategy (pmap, remotecall, @distributed).
function main()
    ...
end
```

This two-function contract is the only coupling between `runner.jl` and experiment scripts; keep it stable across any future extraction.

## Extraction status

| Concern | Status |
|---|---|
| Shared code in a module | Done — `src/ParallelRunnerKit.jl` |
| Arbitrary remote URL / path | Done — `setup.jl --repo` / `--remote-path`, `DISTRIBUTED_REMOTE_PROJECT_ROOT` |
| Worker module name override | Done — `runner.jl --package NAME` |
| `init_output_dir!`/`main()` as a documented public API | Not started (could add a lightweight abstract interface) |
| Register as `DistributedRunner.jl` | Not started (may stay lab-internal/unregistered) |
| `ParallelRunnerKit/Project.toml` is vendoring-only, not the app's env | By design; stub name is unregistered |

## Versioning and reproducibility

- `Project.toml` `version` is exposed as `parallel_runner_kit_version()` / `PARALLEL_RUNNER_KIT_VERSION`, printed at `runner.jl` startup.
- `runner.jl` logs a short git hash for the application project directory.
- With SSH workers, `check_git_hashes` enforces identical full commit hashes unless `--skip-hash-check`. Remote root resolution: `DISTRIBUTED_REMOTE_PROJECT_ROOT` if set, else same absolute path as local.
- **CI:** GitHub Actions (`.github/workflows/CI.yml`) runs `Pkg.test` with coverage on Julia **1.12** and (prerelease channel) **1.13**. Locally: `julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test(; coverage=false)'`. The kit test also checks (almost) every `[deps]` entry in `ParallelRunnerKit/Project.toml` has a matching UUID in the application root `Project.toml` (monorepo layout); `Distributed` is excluded as a Julia-bundled stdlib. SSH/remote probes are not covered by CI.
- **Ideas for later:** version-matching git tags + `CHANGELOG.md`; a committed `Manifest.toml` for stricter environment pinning; worker self-report of version/path after `using`; treat `--skip-hash-check` as audit-only in production.

## What NOT to do

- No simulation-specific logic (`SimulationConfig`, result formats, etc.) — the runner stays simulation-agnostic.
- No non-Julia workers or non-SSH transports — out of scope.
- No auto-retry/fault-tolerance beyond the current heartbeat + connection-stability wait; re-queuing failed tasks is `pmap`'s job at the script level.

## Stability note on Julia 1.12+

`addprocs` with `tunnel=true` and many SSH workers can return before all TCP
connections are fully registered. `runner.jl` works around this with
`DISTRIBUTED_INIT_DELAY_SEC` (default 5s) and per-worker ping retries
(default 6). Treat this as still relevant on 1.13 until proven otherwise on
real multi-host runs.
