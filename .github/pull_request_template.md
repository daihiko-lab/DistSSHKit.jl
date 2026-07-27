## Summary

<!-- What changed and why -->

## Type

- [ ] New feature
- [ ] Bug fix
- [ ] Documentation
- [ ] Refactoring / internal cleanup
- [ ] CI / dependencies
- [ ] Other:

## Breaking change?

- [ ] No
- [ ] Yes (affects CLI subcommands, module name, or the driver contract `init_output_dir!`/`main`; bump the `x` in `Project.toml`'s `0.x.y` version)

## Tested?

- [ ] Ran `julia --project=. -e 'using Pkg; Pkg.test()'` and it passed
- [ ] If applicable, verified with a manual smoke test (e.g. `runner --local 2 demos/*.jl`)
- [ ] If this touches remote execution (runner/setup), verified against a real remote host
- [ ] If applicable, ran `jetls check` (for reference; not a required check)

## Notes

<!-- Anything reviewers should pay attention to, known limitations, etc. (optional) -->
