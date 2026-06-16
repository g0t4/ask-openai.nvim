local log = require("devtools.logs.logger").universal()

local M = {}

---@param description string
---@return MCP_CallToolSuccessResponse
function M.create_tool_call_output_for_error_message(description)
    local caller = debug.getinfo(2)
    log:error("tool_call plumbing failure: " .. description, "caller: ", vim.inspect(caller))

    -- TODO review all of TOOLs pipeline for other spots to add this

    return {
        result = {
            isError = true,
            content = {
                M.text_content(description, "error")
            },
        },
    }

    -- https://modelcontextprotocol.io/specification/2025-06-18/server/tools#error-handling
    --   could use a "protocol error" though I'd have to patch the "error" through to the model
    --   as long as the model gets the message, it doesn't really matter the format
end

---@param content MCP_ContentBlock[]
---@return MCP_CallToolSuccessResponse
function M.create_tool_call_output_for_error(content)
    return {
        isError = true,
        result = {
            content = content
        },
    }
end

---@param content MCP_ContentBlock[]
---@return MCP_CallToolSuccessResponse
function M.create_tool_call_output_for_success(content)
    return {
        result = {
            content = content
        },
    }
end

---@param value string
---@param name? string -- optional
---@return MCP_TextContent
function M.text_content(value, name)
    if name then
        return { type = "text", text = value, name = name }
    end
    return { type = "text", text = value, }
end

return M
