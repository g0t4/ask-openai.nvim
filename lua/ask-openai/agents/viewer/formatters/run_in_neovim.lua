local safely = require("ask-openai.helpers.safely")
local base = require("ask-openai.agents.viewer.formatters.base")

local M = {}

---@type ToolCallFormatter
function M.format(lines, tool_call, message)
    base.add_generic_header(lines, tool_call)

    local func = tool_call["function"]
    local args = func.arguments
    if args then
        local ok, decoded = safely.decode_json(args)
        if ok and type(decoded) == "table" and decoded.lua then
            lines:append_text_fold_if_long("LUA", decoded.lua)
        else
            lines:append_text(args)
        end
    end

    -- * progress messages (shown when tool is still running)
    local is_tool_done = tool_call:is_done()
    base.render_progress(lines, tool_call, is_tool_done)

    if not is_tool_done then
        return
    end

    base.render_tool_result(lines, tool_call)
end

return M
