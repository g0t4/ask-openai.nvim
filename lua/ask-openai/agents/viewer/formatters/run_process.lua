local log = require("devtools.logs.logger").universal()
local HLGroups = require("ask-openai.hlgroups")
local safely = require("ask-openai.helpers.safely")
local argv_formatter = require("ask-openai.agents.viewer.formatters.argv_formatter")
local base = require("ask-openai.agents.viewer.formatters.base")

local M = {}

--- Format the command header text for a run_process tool call.
---
---@param args_json string
---@param message RxAccumulatedMessage
---@return string: header
---@return table?: decoded_args
local function get_tool_header_text(args_json, message)
    if message:is_still_streaming() then
        return args_json, nil
    end

    local success, object_or_error = safely.decode_json(args_json)
    if not success then
        return "json decode failure (see logs): " .. vim.inspect(object_or_error), nil
    end

    local command_line = object_or_error.command_line
    if command_line then
        object_or_error.command_line = nil
        return command_line, object_or_error
    end

    local argv = object_or_error.argv
    if argv then
        object_or_error.argv = nil
        local cmd = argv_formatter.commandline_equivalent_for_argv(argv)
        return cmd, object_or_error
    end

    -- Fallback: try the full formatter (includes ambiguity check, legacy command)
    local format_ok, formatted_cmd = pcall(function()
        return argv_formatter.format_run_process_command(args_json)
    end)
    if format_ok then
        return formatted_cmd, object_or_error
    end

    log:error("failed to format run_process command", args_json)
    return "command format error: " .. args_json, object_or_error
end

---@type ToolCallFormatter
local function add_tool_header(lines, tool_call, message)
    local header, decoded_args = get_tool_header_text(tool_call["function"].arguments, message)
    base.add_generic_header(lines, tool_call, header)
    return decoded_args
end

---@type ToolCallFormatter
function M.format(lines, tool_call, message)
    local decoded_args = add_tool_header(lines, tool_call, message)
    if decoded_args then
        -- PRN add indication that these are inputs? right now they blend in with outputs... (color?)
        if decoded_args.stdin then
            lines:append_text_fold_if_long("STDIN", decoded_args.stdin)
            decoded_args.stdin = nil
        end

        for key, value in pairs(decoded_args) do
            -- other inputs: cwd, stdin, timeout_ms, dry_run (I'd be fine w/ hiding timeout_ms and dry_run if false)
            lines:append_text(key .. ": " .. vim.inspect(value))
        end
    end

    -- -- debug dump everything:
    -- lines:append_text(vim.inspect(tool_call))

    -- * progress messages (shown when tool is still running)
    local is_tool_done = tool_call:is_done()
    base.render_progress(lines, tool_call, is_tool_done)

    if not is_tool_done then
        return
    end

    -- * tool result
    local has_structured_content = tool_call.call_output.result.structuredContent
    if has_structured_content then
        --- https://modelcontextprotocol.io/specification/2025-06-18/server/tools#tool-result

        -- * TESTING:
        -- - date command is one liner
        -- - `ls -R` for lots of output

        ---@type MCP_ContentBlock[]
        local structuredContent = tool_call.call_output.result.structuredContent
        local keys = vim.tbl_keys(structuredContent)
        log:info("structuredContent", structuredContent)
        for _, key_raw in ipairs(keys) do
            local value = structuredContent[key_raw]
            if type(value) ~= "string" then
                log:warn("unexpected value type in run_bash/run_xonsh formatter... heads up in case you want to handle it different, key:" .. key_raw, ", value:", value)
                value = vim.inspect(value)
            end
            local skip = value == vim.NIL
            if not skip then
                local display_key = key_raw:upper()
                if display_key == "STDOUT" or display_key == "STDERR" then
                    lines:append_text_fold_if_long(display_key, tostring(value))
                else
                    local is_multi_line = value:match("\n")
                    if is_multi_line then
                        lines:append_text(display_key)
                        lines:append_text(value)
                    else
                        -- single line
                        lines:append_text(display_key .. ": " .. value)
                    end
                end
            end
        end
    else
        lines:append_text("unexpected tool result type in run_bash/run_xonsh formatter")
        lines:append_text(vim.inspect(tool_call.call_output))
        log:error("unexpected tool result type in run_bash/run_xonsh formatter", tool_call.call_output)
    end
end

return M
