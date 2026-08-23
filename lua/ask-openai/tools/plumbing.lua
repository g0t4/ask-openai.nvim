local log = require("devtools.logs.logger").universal()

local M = {}

---@param description string
---@return MCP_CallToolResponse
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
---@return MCP_CallToolResponse
function M.create_tool_call_output_for_error(content)
    return {
        result = {
            isError = true,
            content = content
        },
    }
end

---@param content MCP_ContentBlock[]
---@return MCP_CallToolResponse
function M.create_tool_call_output_for_success(content)
    return {
        result = {
            content = content
        },
    }
end

--- generic cancel response,
--- usually a model does not get tool call results after interrupt/stop
--- but if you cancel using a different mechanism then they will at least receive the message
---@param message string
---@return MCP_CallToolResponse
function M.create_tool_call_output_for_canceled(message)
    return {
        -- Wes invented this response
        isError = true,
        result = {
            content = { M.text_content(message, "canceled") }
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
