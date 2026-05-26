local HLGroups = require("ask-openai.hlgroups")
local safely = require("ask-openai.helpers.safely")
local generic = require("ask-openai.agents.viewer.formatters.generic")

local M = {}

---@type ToolCallFormatter
function M.format(lines, tool_call, message)
    -- Header (similar to generic formatter)
    local func = tool_call["function"]
    local name = func.name or "run_lua"
    local hl_group = HLGroups.TOOL_SUCCESS
    if tool_call.call_output then
        if tool_call.call_output.result.isError then
            name = "❌ " .. name
            hl_group = HLGroups.TOOL_FAILED
        else
            name = "✅ " .. name
        end
    end
    lines:append_styled_text(name, hl_group)

    -- Arguments: attempt to decode JSON and pretty‑print the Lua code
    local args = func.arguments
    if args then
        local ok, decoded = safely.decode_json(args)
        if ok and type(decoded) == "table" and decoded.code then
            -- Show the code, folding long blocks
            lines:append_text_fold_if_long("CODE", decoded.code)
        else
            -- Fallback to raw argument string
            lines:append_text(args)
        end
    end

    -- If the tool hasn't finished yet, indicate pending state
    if not tool_call:is_done() then
        lines:append_unexpected_line("Tool call in progress...")
        return
    end

    -- Tool result handling (mirrors generic.format without adding another header)
    local is_mcp = tool_call.call_output and tool_call.call_output.result.content
    if is_mcp then
        ---@type MCPToolResultContent[]
        local content = tool_call.call_output.result.content
        for _, output in ipairs(content) do
            local name = output.name
            local text = tostring(output.text or "")
            if name == "STDOUT" then
                if text ~= "" then
                    lines:append_text_fold_if_long("STDOUT", text)
                else
                    lines:append_unexpected_line("UNEXPECTED empty STDOUT?")
                end
            else
                if name == nil or name == "" then
                    name = "[NO NAME]"
                end
                if output.type == "text" then
                    if text:match("\n") then
                        lines:append_text(name)
                        lines:append_text(text)
                    else
                        lines:append_text(name .. ": " .. text)
                    end
                else
                    lines:append_unexpected_text("  UNEXPECTED type: \n" .. vim.inspect(output))
                end
            end
        end
    else
        -- Non‑MCP tool results – currently not specially formatted
        -- fallback: show raw result if available
        if tool_call.call_output then
            lines:append_text(vim.inspect(tool_call.call_output))
        end
    end
end

return M
