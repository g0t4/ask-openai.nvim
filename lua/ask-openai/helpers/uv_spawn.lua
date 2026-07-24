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
