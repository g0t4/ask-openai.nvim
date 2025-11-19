local log = require("ask-openai.logs.logger").predictions()
local HLGroups = require("ask-openai.hlgroups")

local M = {}

---@type ToolCallFormatter
function M.format(lines, tool_call, message)
    -- if message:is_still_streaming() then
    --     -- TODO?
    --     -- TODO OR message:get_lifecycle_step() == RxAccumulatedMessage.RX_LIFECYCLE.FINISHED
    --     return
    -- end

    local tool_header = tool_call["function"].name or ""

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

    -- * tool args
    local args = tool_call["function"].arguments
    if args then
        lines:append_text(args)
    end
    -- PRN mark outputs somehow? or just dump them? (I hate to waste space)

    -- * tool result
    if not tool_call:is_done() then
        -- PRN for slow tools, use thinking dots ... as calling dots!
        lines:append_unexpected_line("Tool call in progress...")
        return
    end

    local is_mcp = tool_call.call_output and tool_call.call_output:is_mcp()
    if is_mcp then
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
