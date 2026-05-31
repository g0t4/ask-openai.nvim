local HLGroups = require("ask-openai.hlgroups")
local safely = require("ask-openai.helpers.safely")
local base = require("ask-openai.agents.viewer.formatters.base")

local M = {}

--- Decode and extract key fields from delegate tool arguments.
---
---@param args_json string
---@param message RxAccumulatedMessage
---@return table? decoded_args
local function decode_delegate_args(args_json, message)
    if message:is_still_streaming() then
        return nil
    end

    local success, decoded = safely.decode_json(args_json)
    if not success or type(decoded) ~= "table" then
        return nil
    end

    return decoded
end

--- Render the description as a markdown blockquote-style line.
---
---@param description string
local function render_description(description)
    -- Wrap in a > ... blockquote-style format
    local lines = vim.split(description, "\n")
    for i, line in ipairs(lines) do
        lines[i] = "> " .. line
    end
    return table.concat(lines, "\n")
end

--- Check if a value should be displayed (non-nil, non-zero, non-false).
---
---@param value any
---@return boolean
local function should_display(value)
    if value == nil then return false end
    if type(value) == "number" and value == 0 then return false end
    if value == false then return false end
    return true
end

---@type ToolCallFormatter
function M.format(lines, tool_call, message)
    local func_name = tool_call["function"].name or "delegate"
    local hl_group = HLGroups.TOOL_SUCCESS

    -- * decode args to get agent_type for title
    local decoded_args = decode_delegate_args(tool_call["function"].arguments, message)
    if decoded_args and decoded_args.agent_type then
        func_name = string.format("%s (%s)", func_name, decoded_args.agent_type)
    end

    -- * status indicator
    if tool_call.call_output then
        if tool_call.call_output.result and tool_call.call_output.result.isError then
            func_name = "❌ " .. func_name
            hl_group = HLGroups.TOOL_FAILED
        else
            func_name = "✅ " .. func_name
        end
    end

    lines:append_styled_text(func_name, hl_group)

    -- * decode and display arguments
    decoded_args = decoded_args or decode_delegate_args(tool_call["function"].arguments, message)
    if decoded_args then
        -- Description (most important field - show as blockquote)
        local description = decoded_args.description
        if description and #description > 0 then
            lines:append_text(render_description(description))
        end

        -- Recursion limit (only show if set)
        local recursion_limit = decoded_args.recursion_limit
        if should_display(recursion_limit) then
            lines:append_text(string.format("recursion_limit: %d", recursion_limit))
        end

        -- Show any other keys that aren't description, recursion_limit, or agent_type
        for key, value in pairs(decoded_args) do
            if key ~= "description" and key ~= "recursion_limit" and key ~= "agent_type" then
                local value_str = type(value) == "string" and value or vim.inspect(value)
                lines:append_text(key .. ": " .. value_str)
            end
        end
    end

    -- * progress messages (shown when tool is still running)
    local is_tool_done = tool_call:is_done()
    base.render_progress(lines, tool_call, is_tool_done)

    if not is_tool_done then
        return
    end

    -- * tool result
    local is_mcp = tool_call.call_output and tool_call.call_output.result and tool_call.call_output.result.content
    if is_mcp then
        ---@type MCP_ContentBlock[]
        local content = tool_call.call_output.result.content

        local multiple_outputs = #content > 1
        for _, output in ipairs(content) do
            local name = output.name
            local text = tostring(output.text or "")
            if not text then
                if name then
                    lines:append_text(name)
                else
                    lines:append_text("[ empty text ]")
                end
            elseif output.type == "text" then
                local is_multi_line = text:match("\n")
                if is_multi_line then
                    if name then
                        lines:append_text(name .. ":")
                        lines:append_text(text)
                    else
                        lines:append_text(text)
                    end
                else
                    if name then
                        lines:append_text(name .. ": " .. text)
                    else
                        lines:append_text(text)
                    end
                end
            else
                lines:append_unexpected_text("  UNEXPECTED type: \n" .. vim.inspect(output))
            end
        end
    end
end

return M
