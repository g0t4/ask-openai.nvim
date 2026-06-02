local HLGroups = require("ask-openai.hlgroups")
local base = {}

--- Format a duration in milliseconds into a human-readable string.
---
--- Rules:
---   - < 1000ms: "{N}ms"
---   - < 60000ms (60s): "{X.X}s" (1 decimal, trims trailing .0 if whole number)
---   - >= 60000ms: "{M}m{S}s" (whole minutes + whole seconds)
---
---@param duration_ms integer
---@return string
function base.format_duration_ms(duration_ms)
    if duration_ms < 1000 then
        return duration_ms .. "ms"
    end

    local seconds = duration_ms / 1000.0
    if seconds < 60 then
        -- Round to 1 decimal place
        local rounded_seconds = math.floor(seconds * 10 + 0.5) / 10
        -- Check if it's a whole number after rounding
        if rounded_seconds == math.floor(rounded_seconds) then
            return string.format("%ds", math.floor(rounded_seconds))
        end
        return string.format("%.1fs", rounded_seconds)
    end

    local minutes = math.floor(seconds / 60)
    local whole_seconds = math.floor(seconds % 60)
    return string.format("%dm%ds", minutes, whole_seconds)
end

--- Format the current elapsed time since start_time_ms.
--- Used for in-progress tools to show how long they've been running.
---
---@param start_time_ms integer
---@return string
function base.format_elapsed_time(start_time_ms)
    local now_ms = math.floor(vim.uv.hrtime() / 1e6)
    local elapsed_ms = now_ms - start_time_ms
    if elapsed_ms < 0 then
        return "?ms"
    end
    return base.format_duration_ms(elapsed_ms)
end

--- Render progress notifications for an in-progress tool call.
--- Shows animated spinner, tool name, and up to 3 most recent progress updates.
--- When the tool is done, shows the final duration.
--- Progress notifications are formatted using both argv_formatter (for JSON-style)
--- and notification_formatter (for "Running tool:" style).
---
---@param lines LinesBuilder
---@param tool_call ToolCall
---@param is_done boolean
function base.render_progress(lines, tool_call, is_done)
    if is_done then
        -- * tool is done - show duration
        if tool_call.call_output and tool_call.call_output.duration_ms then
            local duration_str = base.format_duration_ms(tool_call.call_output.duration_ms)
            lines:append_line(duration_str)
        end
        return
    end

    -- Show current progress notification (most recent) with spinner
    local spinner_chars = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
    local current_time = vim.loop.hrtime()
    local spinner_index = math.floor((current_time / 100000000) % #spinner_chars) + 1
    local spinner_char = spinner_chars[spinner_index]

    -- Show header with tool name, spinner, and elapsed time
    local func_name = tool_call["function"].name or "unknown_tool"
    local start_time_ms = tool_call.start_time_ms or 0
    local elapsed_str = base.format_elapsed_time(start_time_ms)
    lines:append_line(string.format("%s ⏳ Running: %s (%s)", spinner_char, func_name, elapsed_str))

    -- Show recent progress notifications (up to 3 most recent)
    local num_progress = #tool_call.progress_notifications
    if num_progress > 0 then
        local max_show = math.min(3, num_progress)
        local start_idx = num_progress - max_show + 1

        if max_show < num_progress then
            lines:append_line(string.format("  ... (%d more messages)", num_progress - max_show))
        end

        for i = start_idx, num_progress do
            local msg = tool_call.progress_notifications[i]
            -- Try argv_formatter first (for JSON-style run_process args)
            local formatted_msg = require("ask-openai.agents.viewer.formatters.argv_formatter").format_progress_message(msg)
            -- Try notification_formatter if argv_formatter didn't change the message
            if formatted_msg == msg then
                formatted_msg = require("ask-openai.agents.viewer.formatters.notification_formatter").format_notification_message(msg)
            end
            -- Truncate very long messages to avoid overwhelming the view
            if #formatted_msg > 200 then
                formatted_msg = formatted_msg:sub(1, 197) .. "..."
            end
            lines:append_line(string.format("    ↳ %s", formatted_msg))
        end
    else
        lines:append_line("    ↳ Waiting for response...")
    end
end

return base
