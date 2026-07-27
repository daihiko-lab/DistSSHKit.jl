# Runner implementation files are always `include`d from `runner.jl` after SSHRunner is loaded.
# Do not `include` SSHRunner here — that duplicates `runner.jl` and triggers IDE DuplicateInclude.
using .SSHRunner
using Dates
using Distributed

if !@isdefined(PROJECT_ROOT)
    const PROJECT_ROOT = get(ENV, "DISTRIBUTED_PROJECT_ROOT", pwd())
end
