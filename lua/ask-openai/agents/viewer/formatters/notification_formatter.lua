local argv_formatter = require("ask-openai.agents.viewer.formatters.argv_formatter")
local safely = require("ask-openai.helpers.safely")

local M = {}

--- Try to parse Python dict-style or JSON-style string into a table.
--- Handles both single-quote Python dicts and double-quote JSON.
---
---@param args_str string: The args string (e.g. "{'path': '/foo'}" or '{"path": "/foo"}')
---@return table|nil: Parsed table if successful, nil otherwise.
local function try_parse_args(args_str)
    if not args_str or #args_str == 0 then
        return nil
    end

    -- Try JSON first (double quotes)
    local ok, parsed = safely.decode_json(args_str)
    if ok and type(parsed) == "table" then
        return parsed
    end

    -- Try Python-style dict (single quotes) - simple conversion
    -- Replace single-quoted strings with double-quoted for JSON parsing
    local converted = args_str:gsub("'", '"')
    -- Handle nested single quotes in values by finding patterns like 'key': 'value'
    ok, parsed = safely.decode_json(converted)
    if ok and type(parsed) == "table" then
        return parsed
    end

    return nil
end

--- Format ls tool notification.
---
---@param args table: Tool arguments.
---@return string: Formatted command string.
local function format_ls(args)
    local path = args.path or "?"
    return "ls " .. (path:match("%s") and '"' .. path .. '"' or path)
end

--- Format read_file tool notification.
---
---@param args table: Tool arguments.
---@return string: Formatted command string.
local function format_read_file(args)
    local file_path = args.file_path or "?"
    return "read_file " .. (file_path:match("%s") and '"' .. file_path .. '"' or file_path)
end

--- Format write_file tool notification.
---
---@param args table: Tool arguments.
---@return string: Formatted command string.
local function format_write_file(args)
    local file_path = args.file_path or "?"
    return "write_file " .. (file_path:match("%s") and '"' .. file_path .. '"' or file_path)
end

--- Format glob tool notification.
---
---@param args table: Tool arguments.
---@return string: Formatted command string.
local function format_glob(args)
    local pattern = args.pattern or "?"
    local pattern_part = pattern:match("%s") and '"' .. pattern:gsub('"', '\\"') .. '"' or pattern
    if args.path and #args.path > 0 then
        local path_part = args.path:match("%s") and '"' .. args.path:gsub('"', '\\"') .. '"' or args.path
        return "glob " .. pattern_part .. " in " .. path_part
    end
    return "glob " .. pattern_part
end

--- Format execute tool notification.
--- Uses the `command` field to show the actual command.
---
---@param args table: Tool arguments.
---@return string: Formatted command string.
local function format_execute(args)
    local command = args.command or ""
    -- If command has spaces, wrap in quotes for clarity
    if command:match("%s") then
        command = '"' .. command:gsub('"', '\\"') .. '"'
    end
    return command
end

--- Format search tool notification.
---
---@param args table: Tool arguments.
---@return string: Formatted command string.
local function format_search(args)
    local query = args.query or args.q or "?"
    return "search " .. (query:match("%s") and '"' .. query:gsub('"', '\\"') .. '"' or query)
end

--- Format edit_file tool notification.
---
---@param args table: Tool arguments.
---@return string: Formatted command string.
local function format_edit_file(args)
    local file_path = args.file_path or "?"
    return "edit_file " .. (file_path:match("%s") and '"' .. file_path .. '"' or file_path)
end

--- Tool-specific dispatch table.
--- Each key is a tool name, each value is a formatter function.
---
---@type table<string, fun(args: table): string>
local tool_formatters = {
    ["ls"] = format_ls,
    ["read_file"] = format_read_file,
    ["write_file"] = format_write_file,
    ["edit_file"] = format_edit_file,
    ["glob"] = format_glob,
    ["execute"] = format_execute,
    ["search"] = format_search,
}

--- Register a custom tool formatter for a specific tool name.
--- Allows extensibility without modifying the core dispatch table.
---
---@param tool_name string: The tool name to register (e.g. "ls", "read_file")
---@param formatter_fn fun(args: table): string: A function that takes parsed args and returns a formatted string.
function M.register_tool_formatter(tool_name, formatter_fn)
    tool_formatters[tool_name] = formatter_fn
end

--- Format a progress notification message for a tool execution.
--- Recognizes the "Running tool: <name> args=<args>" format and dispatches
--- to the appropriate tool-specific formatter.
---
--- For `run_process`, delegates to argv_formatter.format_progress_message()
--- since it already handles the complex argv/command_line formatting.
---
--- Unknown tools or unrecognized formats fall back to returning the original message.
---
---@param msg string: The progress notification message string.
---@return string: The formatted notification, or the original message if unparseable.
function M.format_notification_message(msg)
    if not msg or #msg == 0 then
        return msg
    end

    -- Check if it looks like a "Running tool:" notification
    -- Pattern: "Running tool: <tool_name> args=<args>"
    -- Capture both tool_name and args separately
    local tool_name, args_str = msg:match("^%s*Running tool:%s+(%S+)%s+args=(.+)$")
    if not tool_name then
        return msg
    end

    -- Dispatch to tool-specific formatter
    local formatter_fn = tool_formatters[tool_name]
    if not formatter_fn then
        -- Unknown tool - return original message
        return msg
    end

    -- Special case: run_process delegates to argv_formatter
    if tool_name == "run_process" then
        return argv_formatter.format_progress_message(msg)
    end

    -- Parse args and format
    local args = try_parse_args(args_str)
    if not args then
        -- Failed to parse args - return original
        return msg
    end

    local formatted = formatter_fn(args)
    if not formatted or #formatted == 0 then
        return msg
    end

    return formatted
end

return M
