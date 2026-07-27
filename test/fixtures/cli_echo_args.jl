# Test fixture for `_run_kit_cli_script`: records ARGS after the bridge sets them.
path = get(ENV, "_PRK_TEST_ARGS_FILE", "")
if !isempty(path)
    open(path, "w") do io
        for arg in ARGS
            println(io, arg)
        end
    end
end
