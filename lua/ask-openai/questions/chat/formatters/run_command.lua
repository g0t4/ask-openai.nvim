local log = require("ask-openai.logs.logger").predictions()
local HLGroups = require("ask-openai.hlgroups")

local M = {}

---@type ToolCallFormatter
function M.format(lines, tool_call, message)
    local args_json = tool_call["function"].arguments

    local tool_header = args_json -- default show the JSON as the tool call is streamed in
    if not message:is_still_streaming() then
        local json_args_parsed, args = xpcall(function()
            return vim.json.decode(args_json)
        end, function() end) -- TODO is there an xpcall alternative that doesn't expect on failure (b/c I don't need a callback in that case)

        if json_args_parsed and args.command then
            tool_header = args.command
        end
    end

    -- TODO extract command from JSON and show if reasonable length?
    --   TODO if LONG then fold the one line b/c with my fold setup a long line can be collapsed
    --      and then the first part of command will be visible
    --   TODO args.command (has full command)
    --   TODO args.workdir
    --   TODO args.STDIN show collapsed?

    local hl_group = HLGroups.TOOL_SUCCESS
    if tool_call.call_output then
        if tool_call.call_output.result.isError then
            tool_header = "❌ " .. tool_header
            hl_group = HLGroups.TOOL_FAILED
        else
            tool_header = "✅ " .. tool_header
        end
    end
    lines:append_styled_lines({ tool_header }, hl_group)

    if not tool_call.call_output then
        -- tool not yet run/running
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
        ---@field type string      # "text", "image", "audio", "resource_link", "resource" ...
        ---@field text? string     # for type=text
        ---@field name? string     # IIUC this is considered optional metadata...  I am using this with my run_command tool for: "STDOUT", "STDERR", "EXIT_CODE"

        -- * TESTING:
        -- - date command is one liner
        -- - `ls -R` for lots of output

        ---@type MCPToolResultContent[]
        local content = tool_call.call_output.result.content

        for _, output in ipairs(content) do
            local name = output.name
            local text = tostring(output.text or "")
            -- PRN dict. lookup of formatter functions by type (name), w/ registerType(), esp. as the list of types grows
            if name == "STDOUT" then
                -- TODO! I want tool specific formatters... b/c for run_command, I want the command (esp if its small) to be the header! I don't need to see run_command ever, right?
                if text then
                    lines:append_STDOUT(text)
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
