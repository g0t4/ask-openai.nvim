local log = require("ask-openai.logs.logger").predictions()
local HLGroups = require("ask-openai.hlgroups")
local safely = require("ask-openai.helpers.safely")

local M = {}

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

    if not object_or_error.mode then
        return "missing mode: ", object_or_error
    end

    local mode = object_or_error.mode
    object_or_error.mode = nil -- only want to pass back remaining args

    if mode == "shell" then
        local command_line = object_or_error.command_line
        object_or_error.command_line = nil
        if command_line then
            return command_line, object_or_error
        end
        return "missing command_line: ", object_or_error
    end

    if mode == "executable" then
        local argv = object_or_error.argv
        if argv then
            local cmd = table.concat(argv, " ")
            object_or_error.argv = nil
            return cmd, object_or_error
        end
        return "missing argv: ", object_or_error
    end

    log:error("invalid mode", args_json)
    return "invalid mode: " .. args_json, object_or_error
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

    if not tool_call.call_output then
        -- tool not yet run/running – indicate pending state
        lines:append_unexpected_line("Tool call in progress...")
        return
    end

    -- * tool result
    local is_mcp = tool_call.call_output.result.content
    if is_mcp then
        --- https://modelcontextprotocol.io/specification/2025-06-18/server/tools#tool-result

        ---@class MCPToolCallOutputResult
        ---@field result MCPToolResult

        ---@class MCPToolCallOutputError
        ---@field error { code, messeage }  -- { "code": 100, "message": "Unknown tool: invalid_tool_name" }

        ---@class MCPToolResult
        ---@field content? MCPToolResultContent[]  # unstructured output items
        ---@field isError? boolean                # see content for exit code, STDERR, etc
        ---@field structuredContent?              # structured output, has inputSchema/outputSchema

        ---@class MCPToolResultContent
        ---@field type string      # "text", "image", "audio", "resource_link", "resource" …
        ---@field text? string     # for type=text
        ---@field name? string     # i.e.: "STDOUT", "STDERR", "EXIT_CODE" … describe the text value

        -- * TESTING:
        -- - date command is one liner
        -- - `ls -R` for lots of output

        ---@type MCPToolResultContent[]
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
