local base = require("ask-openai.agents.viewer.formatters.base")
local safely = require("ask-openai.helpers.safely")

local M = {}

---@type ToolCallFormatter
function M.format(lines, tool_call, message)
    local func = tool_call["function"]
    local header = func.name or "speak"

    base.add_generic_header(lines, tool_call, header)

    -- decode args to show what was spoken
    local decoded_args = nil
    if not message:is_still_streaming() then
        local success, decoded = safely.decode_json(func.arguments or "{}")
        if success then
            decoded_args = decoded
        end
    end

    if decoded_args and decoded_args.text then
        lines:append_text(string.format("🗣️ %s", decoded_args.text))
    end

    -- progress (if still running)
    local is_tool_done = tool_call:is_done()
    base.render_progress(lines, tool_call, is_tool_done)

    if not is_tool_done then
        return
    end

    base.render_tool_result(lines, tool_call)
end

return M
