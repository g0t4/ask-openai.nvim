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
    if text == "" then
        log:warn("skipping empty text block", block)
        return nil
    end
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

    -- log:info("flatten_tool_result_to_text, original result:", result)
    -- Unwrap MCP content blocks into plain text so the model sees raw output
    -- instead of a JSON string containing JSON-escaped strings (JSON-in-JSON).
    local parts = {}
    if result.isError then
        parts[1] = "ERROR"
    end

    local content = result.content
    if type(content) == "string" then
        parts[#parts + 1] = content
    elseif type(content) == "table" then
        for _, block in ipairs(content) do
            local text
            if type(block) == "table" then
                if block.type == "text" then
                    text = flatten_text_block(block)
                elseif block.type == "image" then
                    text = ""
                    -- text = "[image: " .. tostring(block.mimeType or "?") .. "]"
                elseif block.type == "audio" then
                    text = ""
                    -- text = "[audio: " .. tostring(block.mimeType or "?") .. "]"
                elseif block.type == "resource" then
                    local uri = block.resource and block.resource.uri or "?"
                    text = "[resource: " .. tostring(uri) .. "]"
                else
                    vim.notify("unexpected MCP content block type: " .. tostring(block), vim.log.levels.WARN)
                    log:warn("unexpected MCP content block type", block)
                    text = "[unknown block type: " .. tostring(block.type or "?") .. "]"
                end
            else
                vim.notify("oops... unexpected tool result content has an entry that is not a table/object, this should not happen, investigate!")
                log:error("tool result content has an entry that is not a table/object", block)
                text = vim.inspect(block)
            end
            if text ~= "" then
                parts[#parts + 1] = text
            end
        end
    else
        vim.notify("oops... unexpected tool result content is missing")
        log:error("tool result has no content", result)
        -- not intended as long term solution hence notify
        return vim.inspect(result)
    end

    local flat = table.concat(parts, "\n\n")
    -- log:info("flat", flat)
    return flat
end

---@param result MCP_CallToolResult
---@return string[] -- data URLs for every image content block in the result
function M.extract_image_data_urls(result)
    local urls = {}
    if type(result) ~= "table" then
        return urls
    end

    local content = result.content
    if type(content) ~= "table" then
        return urls
    end

    for _, block in ipairs(content) do
        if type(block) == "table" and block.type == "image" and block.data then
            local mime = block.mimeType or "image/png"
            urls[#urls + 1] = "data:" .. mime .. ";base64," .. block.data
        end
    end
    return urls
end

return M
