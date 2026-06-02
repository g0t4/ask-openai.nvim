local M = {}

--- Only adds quotes when the element contains whitespace.
--- Uses double quotes by default, falling back to single quotes
--- or escaped double quotes if both quote types are present.
---
---@param element string: A single argument from the argv array.
---@return string: The element, quoted if it contains whitespace.
local function quote_argv_element(element)
    local has_whitespace = element:match("%s") ~= nil
    if not has_whitespace then
        return element
    end
    if element:find('"', 1, true) == nil then
        return '"' .. element .. '"'
    end
    if element:find("'", 1, true) == nil then
        return "'" .. element .. "'"
    end
    local escaped = element:gsub('"', '\\"')
    return '"' .. escaped .. '"'
end

--- Join argv array into a human-readable string with proper quoting.
---
---@param argv string[]
---@return string
function M.commandline_equivalent_for_argv(argv)
    local quoted = vim.tbl_map(quote_argv_element, vim.tbl_map(tostring, argv))
    return table.concat(quoted, " ")
end

--- Parse run_process arguments and return a displayable command string.
---
--- Supports three modes:
--- - argv: Array of arguments (quoted if they contain whitespace)
--- - command_line: Raw shell command string
---
---@param args_json string: JSON string of arguments from the tool call.
---@return string: A formatted command string ready for display.
---@error string: "Ambiguous run_process - both command_line and argv are set" or "No command found"
function M.format_run_process_command(args_json)
    local ok, obj = pcall(function()
        return vim.json.decode(args_json)
    end)
    if not ok then
        error("JSON decode failed: " .. tostring(obj))
    end

    local command_line = obj.command_line
    local argv = obj.argv or {}
    local command = obj.command -- legacy name

    if command_line and #argv > 0 then
        error("Ambiguous run_process - both command_line and argv are set")
    end

    if command_line then
        return command_line
    end
    if #argv > 0 then
        return M.commandline_equivalent_for_argv(argv)
    end
    if command then
        return command
    end
    error("No command found")
end

--- Attempt to parse a progress message and format it as a command line if possible.
--- This is used to format progress messages from run_process tool calls
--- so they display as readable commands instead of raw JSON.
---
---@param msg string: The progress message string.
---@return string: The formatted command if parseable, otherwise the original message.
function M.format_progress_message(msg)
    -- Quick check: does this look like it could be run_process args?
    -- We check for common key names before attempting full JSON decode
    local is_likely_json = msg:match("^%s*{") ~= nil
    if not is_likely_json then
        return msg
    end

    -- Check if it contains run_process-related keys before decoding
    local has_command_line = msg:match("command_line") ~= nil
    local has_argv = msg:match("argv") ~= nil
    local has_command = msg:match("command") ~= nil

    if not (has_command_line or has_argv or has_command) then
        return msg
    end

    -- Try to parse and format
    local ok, formatted = pcall(function()
        return M.format_run_process_command(msg)
    end)

    if ok then
        return formatted
    end

    -- Failed to parse - return original
    return msg
end

return M
