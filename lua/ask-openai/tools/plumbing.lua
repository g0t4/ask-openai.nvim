local log = require("ask-openai.logs.logger").predictions()

local M = {}

---@param description string
---@return MCPToolCallOutputResult
function M.create_tool_call_output_failure(description)
    log:error("tool_call plumbing failure: " .. description)

    return {
        result = {
            isError = true,
            content = {
                {
                    type = "text",
                    text = description,
                    name = "error",
                },
            },
        },
    }
end

return M
