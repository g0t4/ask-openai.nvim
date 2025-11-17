local log = require("ask-openai.logs.logger").predictions()
local HLGroups = require("ask-openai.hlgroups")

local M = {}

---@param lines LinesBuilder
---@param tool_call ToolCall
function M.format(lines, tool_call)
    local tool_header = tool_call["function"].name or ""

    local hl_group = HLGroups.TOOL_SUCCESS
    if tool_call.response then
        if tool_call.response.result.isError then
            tool_header = "❌ " .. tool_header
            hl_group = HLGroups.TOOL_FAILED
        else
            tool_header = "✅ " .. tool_header
        end
    end
    lines:append_styled_lines({ tool_header }, hl_group)

    -- * tool args
    local args = tool_call["function"].arguments
    if args then
        -- TODO new line in args? s\b \n right?
        lines:append_text(args)
    end
    -- PRN mark outputs somehow? or just dump them? (I hate to waste space)

    -- TODO REMINDER - try/add apply_patch when using gptoss (need to put this elsewhere)
    --    USE BUILT-IN mcp server - https://github.com/openai/gpt-oss/tree/main/gpt-oss-mcp-server
    -- TODO REMINDER - also try/add other tools it uses (python code runner, browser)

    -- * tool result
    if tool_call.response then
        local is_mcp = tool_call.response.result.content
        if is_mcp then
            --- https://modelcontextprotocol.io/specification/2025-06-18/server/tools#tool-result
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
            local content = tool_call.response.result.content

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
    else
        -- no response
        -- PRN in-progress tools (i.e. parallel tool calls and one tool completes)
        -- it's probably best to start segmenting a type of tool's displayer and let it handle in-progress vs done vs w/e
    end
end

return M
