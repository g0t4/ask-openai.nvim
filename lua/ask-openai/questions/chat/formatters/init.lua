local run_process = require("ask-openai.questions.chat.formatters.run_command")
local generic = require("ask-openai.questions.chat.formatters.generic")

local M = {
    generic = generic
}

---@alias ToolCallFormatter fun(lines: LinesBuilder, tool_call: ToolCall, message: RxAccumulatedMessage): nil

---@type table<string, ToolCallFormatter>
local formatters_by_function_name = {
    ["run_process"] = run_process.format,
}
-- ? any issues with tool name overlap b/w different servers? does MCP even propose a way to handle the overlap?

function M.get_formatter(function_name)
    return formatters_by_function_name[function_name]
        or generic.format
end

return M
