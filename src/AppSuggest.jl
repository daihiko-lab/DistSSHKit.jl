module AppSuggest

import ..ParallelRunnerKit: _run_kit_cli_script

function (@main)(args::Vector{String}=copy(ARGS))::Cint
    return _run_kit_cli_script("suggest_workers.jl", args)
end

end # module AppSuggest
