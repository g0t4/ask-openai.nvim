local ToolCall = require("ask-openai.agents.tools.tool_call")

local M = {}

--- Render progress messages for an in-progress tool call.
--- Shows animated spinner, tool name, and up to 3 most recent progress updates.
--- When the tool is done, this is a no-op.
---
---@param lines LinesBuilder
---@param tool_call ToolCall
---@param is_done boolean
function M.render_progress(lines, tool_call, is_done)
    if is_done then
        return
    end

    -- Show current progress message (most recent) with spinner
    local spinner_chars = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
    local current_time = vim.loop.hrtime()
    local spinner_index = math.floor((current_time / 100000000) % #spinner_chars) + 1
    local spinner_char = spinner_chars[spinner_index]

    -- Show header with tool name and spinner
    local func_name = tool_call["function"].name or "unknown_tool"
    lines:append_line(string.format("%s ⏳ Running: %s", spinner_char, func_name))

    -- Show recent progress messages (up to 3 most recent)
    local num_progress = #tool_call.progress_messages
    if num_progress > 0 then
        local max_show = math.min(3, num_progress)
        local start_idx = num_progress - max_show + 1

        if max_show < num_progress then
            lines:append_line(string.format("  ... (%d more messages)", num_progress - max_show))
        end

        for i = start_idx, num_progress do
            local msg = tool_call.progress_messages[i]
            -- Truncate very long messages to avoid overwhelming the view
            if #msg > 200 then
                msg = msg:sub(1, 197) .. "..."
            end
            lines:append_line(string.format("    ↳ %s", msg))
        end
    else
        lines:append_line("    ↳ Waiting for response...")
    end
end

return M
