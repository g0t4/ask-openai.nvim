-- lua/ask-openai/helpers/uv_spawn.lua

local ansi = require("devtools.ansi")
local log = require("devtools.logs.logger").universal()

local M = {}

---@param handle userdata|nil
---@param pid_or_error number|string
---@param error_name string|nil
---@param context_object table
function M.log_if_uv_spawn_failed(handle, pid_or_error, error_name, context_object)
    -- NOTES:
    -- on uv.spawn success - handle == userdata, pid_or_error == number, error_name == nil (IIAC nil)
    -- on uv.spawn failure - handle == nil, pid_or_error == string, error_name == string
    --    uv.spawn silently fails, you have to check the return values for the error (if any)
    --    instead of handle/pid you get nil/error/error_name
    --    i.e. error_name == "ENOENT"

    log:info(
        "uv.spawn results (handle:"
        .. vim.inspect(handle)
        .. ", pid_or_error:"
        .. vim.inspect(pid_or_error)
        .. ", error_name:"
        .. vim.inspect(error_name)
        .. ")"
    )

    -- there might be other conditions, but it seems nil for handle means failure
    -- not sure if handle can have non-nil values and still indicate a failure
    -- PRN could assert pid_or_error is a number
    local spawn_failed = handle == nil
    if spawn_failed then
        local message = "\n\n  " .. ansi.bold("uv.spawn() failed")
            .. "\n    pid_or_error: " .. ansi.white_on_red(vim.inspect(pid_or_error))
            .. "\n    error_name: " .. vim.inspect(error_name)
            .. "\n    handle: " .. vim.inspect(handle)
            .. ansi.yellow(ansi.italic("\n\n  CONTEXT: \n" .. M.indent_lines(vim.inspect(context_object))))
            .. "\n"

        log:error(message)
    end
end

---@param text string
---@param number_of_spaces number?
---@return string
function M.indent_lines(text, number_of_spaces)
    number_of_spaces = number_of_spaces or 2
    local lines = vim.iter(vim.split(text, "\n"))
        :map(function(line) return string.rep(" ", number_of_spaces) .. line end)
        :totable()
    return table.concat(lines, "\n")
end

--- Current Process Env Vars + options.env overrides => formatted as KEY=VALUE strings
---   filters VIRTUAL_ENV* vars to avoid inheriting current value (override VIRTUAL_ENV if you want to set the value, else it won't be set)
---@param options { env?: table<string, string> }
---@return table<string, string>
function M.build_env_vars_for_uv_spawn_format(options)
    -- IIAC MCP client config's "env" key is intended to add/OVERRIDE env vars
    --  ... and NOT to fully define the ENV (IOTW does NOT block inheriting parent's ENV)
    --
    -- MCP client config docs:
    --    https://modelcontextprotocol.io/docs/develop/build-client#mcp-client-configuration (example shows API key only)
    -- BTW also MCP registry "spec" which would settle what all fields should be used for max interop

    -- I am mirroring that behavior below (inherit + override):

    local inherit_env = vim.loop.os_environ()

    -- * do not inherit select env vars
    -- this must come before overrides so the client config can still set a value
    for var_name in pairs(inherit_env) do
        -- * block inheriting (VIRTUAL_ENV) python venv
        -- also, always bignore lock the current VENV so python MCP servers use their own
        -- I need this cuz I auto venv in fish shell as I change directories and thus neovim has my auto venv too
        if var_name:sub(1, 11) == "VIRTUAL_ENV" then
            log:info("DROPPING ENV VAR", var_name)
            inherit_env[var_name] = nil
        end
        -- PRN any other env vars to block inheriting?
    end

    local env_overrides = options.env or {}
    local merged_env = vim.tbl_extend("force", inherit_env, env_overrides)
    -- log:info("merged_env", merged_env)

    -- build key=value strings b/c you can't pass a table of key/value pairs to uv.spawn
    ---@type string[]
    local flattened_key_value_env_vars = {}
    for key, value in pairs(merged_env) do
        table.insert(flattened_key_value_env_vars, key .. "=" .. value)
    end
    -- log:info("flattened_key_value_env_vars", flattened_key_value_env_vars)
    return flattened_key_value_env_vars
end

---@param command string
---@param options { args?: string[], stdio?: table[], env?: table<string, string> }
---@param on_exit function(code: integer, signal: integer)
---@return uv.uv_process_t? handle, string|integer pid_or_error, string? error_name
function M.uv_spawn(command, options, on_exit)
    -- BTW get hover help for .spawn and scroll down to second overload (shows three return values, first only shows two which is likely part of why I initially missed that spawn returns errors!)
    local handle, pid_or_error, error_name = vim.uv.spawn(command, options, on_exit)
    M.log_if_uv_spawn_failed(handle, pid_or_error, error_name, {
        command = command,
        args = options.args,
        env = options.env,
        stdio = options.stdio,
    })
    return handle, pid_or_error, error_name
end

return M
