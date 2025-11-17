local run_command = require("ask-openai.questions.chat.formatters.run_command")
local generic = require("ask-openai.questions.chat.formatters.generic")

local M = {
    generic = generic
}

---@alias ToolCallFormatter fun(lines: LinesBuilder, tool_call: ToolCall, message: ChatMessage) -> nil

---@type table<string, ToolCallFormatter>
local formatters_by_function_name = {
    ["run_command"] = run_command.format,
}
-- ? any issues with tool name overlap b/w different servers? does MCP even propose a way to handle the overlap?

function M.get_formatter(function_name)
    return formatters_by_function_name[function_name]
end

return M
