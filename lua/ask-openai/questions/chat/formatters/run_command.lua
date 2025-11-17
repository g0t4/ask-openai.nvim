local log = require("ask-openai.logs.logger").predictions()

local M = {}

---@param lines LinesBuilder
---@param tool_call ToolCall
function M.format(lines, tool_call)
    lines:append_styled_lines({ "RUN_COMMAND" }, "Normal")
    log:info("RUN_COMMAND")
    -- TODO!
end

return M
