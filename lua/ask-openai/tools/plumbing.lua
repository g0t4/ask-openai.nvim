local log = require("ask-openai.logs.logger").predictions()

local M = {}

---@param description string
---@return MCPToolCallOutputResult
function M.create_tool_call_output_failure(description)
    log:error("tool_call plumbing failure: " .. description)

    -- TODO review all of TOOLs pipeline for other spots to add this

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

    -- https://modelcontextprotocol.io/specification/2025-06-18/server/tools#error-handling
    --   could use a "protocol error" though I'd have to patch the "error" through to the model
    --   as long as the model gets the message, it doesn't really matter the format
end

return M
