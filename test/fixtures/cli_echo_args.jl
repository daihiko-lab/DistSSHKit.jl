# Test fixture for `_run_kit_cli_script`: records ARGS after the bridge sets them.
function _write_cli_echo_args!(path::String)
    open(path, "w") do io
        for arg in ARGS
            println(io, arg)
        end
    end
end

let path = get(ENV, "_PRK_TEST_ARGS_FILE", "")
    if !isempty(path)
        _write_cli_echo_args!(path)
    end
end
