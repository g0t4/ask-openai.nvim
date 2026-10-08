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

---@param block MCP_ContentBlock
local function flatten_text_block(block)
    local text = block.text or ""
    local name = block.name or ""
    if name == "" then
        return text
    end
    if name == "EXIT_CODE" then
        return name .. ": " .. text
    end
    return name .. ":\n" .. text
end

---@param result MCP_CallToolResult
---@return string
function M.flatten_tool_result_to_text(result)
    if type(result) ~= "table" then
        return tostring(result)
    end

    -- Unwrap MCP content blocks into plain text so the model sees raw output
    -- instead of a JSON string containing JSON-escaped strings (JSON-in-JSON).
    local parts = {}
    local content = result.content
    if type(content) == "table" then
        for _, block in ipairs(content) do
            if type(block) == "table" then
                local text
                if block.type == "text" then
                    text = flatten_text_block(block)
                elseif block.type == "image" then
                    text = "[image: " .. tostring(block.mimeType or "?") .. "]"
                elseif block.type == "audio" then
                    text = "[audio: " .. tostring(block.mimeType or "?") .. "]"
                elseif block.type == "resource" then
                    local uri = block.resource and block.resource.uri or "?"
                    text = "[resource: " .. tostring(uri) .. "]"
                else
                    vim.notify("unexpected MCP content block type: " .. tostring(block), vim.log.levels.WARN)
                    log:warn("unexpected MCP content block type", block)
                    text = "[unknown block type: " .. tostring(block.type or "?") .. "]"
                end
                parts[#parts + 1] = text
            else
                vim.notify("oops... unexpected tool result content has an entry that is not a table/object, this should not happen, investigate!")
                log:error("tool result content has an entry that is not a table/object", block)
                parts[#parts + 1] = vim.inspect(block)
            end
        end
    end

    local text = table.concat(parts, "\n\n")
    if result.isError then
        text = "ERROR:\n" .. text
    end
    return text
end

return M
