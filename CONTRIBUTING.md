# Contributing

日本語版: [CONTRIBUTING.ja.md](CONTRIBUTING.ja.md)

This document summarizes what to check before opening a PR. For end-user usage, see [README.md](README.md).

## Environment

Development and testing is done on macOS only (other OSes are untested). Requires Julia 1.12+ (CI tests against both `1.12` and `~1.13.0-0`). Changes involving remote hosts also require Julia 1.12+ on each host, and Git, OpenSSH (`ssh`), and rsync on the local side (see the README's [Using remote hosts](README.md#using-remote-hosts) section for details).

Note: the implementation shells out to `ssh`/`rsync`/POSIX commands (e.g. `find`), both locally and on remote hosts, so macOS and Linux are theoretically the only OSes likely to work. Windows isn't accounted for anywhere except the path-separator display logic in `src/DistSSHKit/display.jl` (`Sys.iswindows()`), so it's unsupported (though it might work under WSL). `--local`-only usage (no SSH) should in principle be OS-independent, but this is untested.

## Setup

If you're developing the kit on its own:

```bash
git clone https://github.com/daihiko-lab/DistSSHKit.jl.git ~/dev/DistSSHKit.jl
cd ~/dev/DistSSHKit.jl
```

If you want to edit the kit's code while using it from another project, clone it anywhere and point `Pkg.develop` at that path:

```bash
git clone https://github.com/daihiko-lab/DistSSHKit.jl.git ~/dev/DistSSHKit.jl
cd MyProject.jl
julia --project=. -e 'using Pkg; Pkg.develop(path=expanduser("~/dev/DistSSHKit.jl"))'
```

Same call interface as `Pkg.add` (`julia -m DistSSHKit runner ...`, etc.). Edits in that checkout take effect immediately.

## Branching & commits

- Don't push directly to `main` (branch protection rejects it). Open a PR from a branch like `feature/xxx`, `fix/xxx`, `docs/xxx`, `chore/xxx`
- If your change is breaking (CLI subcommand names, module name, the driver contract `init_output_dir!`/`main`, etc.), bump the `x` in `Project.toml`'s `0.x.y` version. Patch (`y`) bumps are for non-breaking changes only (per Julia's SemVer convention, `x` acts as the effective major version while the package is `0.x`)
- `Pkg.add(url=..., rev=...)` and `Pkg.develop(path=...)` both make you explicitly choose the version's source of truth, unlike General Registry's automatic `[compat]`-driven resolution. That's a deliberate fit for research use (pin an exact commit, keep it reproducible)

## Before opening a PR

```bash
# 1. Tests
julia --project=. -e 'using Pkg; Pkg.test()'

# 2. Static analysis (for reference only; requires jetls on PATH. If the file
#    layout changes, update the same command in .github/workflows/jetls.yml too)
jetls check demos/*.jl src/DistSSHKit.jl src/runner.jl src/setup.jl src/suggest_workers.jl test/*.jl test/fixtures/*.jl

# 3. Manual smoke test (same as the README quick start)
julia --project=. -m DistSSHKit runner --local 2 demos/param_sweep.jl
julia --project=. -m DistSSHKit runner --local 2 demos/coin_flip.jl

# 4. If your change touches remote execution (runner/setup), also verify against a real host
julia --project=. -m DistSSHKit setup --check HOST ...
julia --project=. -m DistSSHKit runner HOST:2 demos/param_sweep.jl
```

`Pkg.test()` already covers the demo scripts themselves (`test/test_demos.jl`) and `demo install`/`demo list` (`test/test_demo_cli.jl`). Steps 2 and 3 are extra checks before pushing. Step 4 is only required when you touched SSH-based behavior (connection, git sync, worker startup, etc.) that `--local` can't exercise.

CI (`test (1.12)`, `test (~1.13.0-0)`) must pass before merging (branch protection). `jetls` isn't a required check; treat it as a reference signal.

## Merging

- Review approval isn't required, but write a PR description that clearly conveys the change (follow this repo's PR template)
- Whether a merge needs a new tag (`vX.Y.Z`) is decided by the maintainers (`yamanori99`)

## Language policy

- Code files (`.jl`) — comments, docstrings, error messages, etc. — should be English only
- Documentation (README, CONTRIBUTING, etc.) is maintained in both English and Japanese, since contributors are often working in a Japanese-speaking environment. When adding or changing a doc, update the corresponding `*.ja.md` (or Japanese counterpart) too
- Generative AI may be used to draft either language version of a doc, but you must verify the content yourself (see "AI-assisted development" below)

## AI-assisted development

This repo allows development with generative AI (LLMs). When opening a PR, make sure you personally understand and have verified any AI-generated code or documentation before submitting it (avoid unreviewed "vibe-coding"). See the README's [Development with generative AI](README.md#development-with-generative-ai) section for background. Also avoid overblown wording or decoration in documentation.
