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

    local success, object_or_error = safely.decode_json_always_logged(args_json)
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
    local hl_group = HLGroups.TOOL_SUCCESS
    if tool_call.call_output then
        if tool_call.call_output.result.isError then
            header = "❌ " .. header
            hl_group = HLGroups.TOOL_FAILED
        else
            header = "✅ " .. header
        end
    end
    -- gptoss sometimes uses a heredoc for a python script
    --   with \n between python statements
    --   stuffed in the command field!
    --   (anything to not use the stdin arg, lol)
    lines:append_styled_text(header, hl_group)
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
    local is_mcp = tool_call.call_output.result.content
    if is_mcp then
        --- https://modelcontextprotocol.io/specification/2025-06-18/server/tools#tool-result

        -- * TESTING:
        -- - date command is one liner
        -- - `ls -R` for lots of output

        ---@type MCP_ContentBlock[]
        local content = tool_call.call_output.result.content

        for _, output in ipairs(content) do
            local name = output.name
            local text = tostring(output.text or "")
            -- PRN dict. lookup of formatter functions by type (name), w/ registerType(), esp. as the list of types grows
            -- run_process
            if name == "STDOUT" then
                -- TODO! I want tool specific formatters... b/c for run_command, I want the command (esp if its small) to be the header! I don't need to see run_command ever, right?
                if text then
                    lines:append_text_fold_if_long("STDOUT", text)
                else
                    -- PRN skip STDOUT entirely if empty?
                    lines:append_unexpected_line("UNEXPECTED empty STDOUT?")
                end
            else
                -- GENERIC output type
                if name == nil or name == "" then
                    name = "[NO NAME]" -- heads up for now so I can identify scenarios/tools, can remove this later
                end
                if output.type == "text" then
                    local is_multi_line = text:match("\n")
                    if is_multi_line then
                        lines:append_text(name)
                        lines:append_text(text)
                    else
                        -- single line
                        lines:append_text(name .. ": " .. text)
                    end
                else
                    lines:append_unexpected_text("  UNEXPECTED type: \n" .. vim.inspect(output))
                end
            end
        end
    else
        -- TODO NON-MCP tool responses
        --  i.e. in-process tools: rag_query, apply_patch
    end
end

return M
