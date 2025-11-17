local log = require('ask-openai.logs.logger').predictions()

--- see https://platform.openai.com/docs/api-reference/chat/create
---@class ChatThread
---@field messages ChatMessage[]
---@field params ChatParams
---@field last_request LastRequest
---@field base_url string
local ChatThread = {}

--- @param messages ChatMessage[]
--- @param params ChatParams
function ChatThread:new(messages, params, base_url)
    self = setmetatable({}, { __index = ChatThread })
    self.messages = messages or {}
    -- FYI think of params as the next request params
    self.params = params or {}
    -- if I want a history of requests I can build that separately
    self.last_request = nil

    self.base_url = base_url
    return self
end

--- @param request LastRequest
function ChatThread:set_last_request(request)
    self.last_request = request
end

--- @param message ChatMessage
function ChatThread:add_message(message)
    if not message.role then
        error("message.role is required")
    end
    table.insert(self.messages, message)
end

----@return table body
function ChatThread:next_curl_request_body()
    local body = {
        -- TODO clone so I can manipulate messages sent back?
        messages = self.messages,
    }
    -- TODO handle when to send thinking back? for gpt-oss tool use in CoT
    -- merge params onto root of body:
    for k, v in pairs(self.params) do
        body[k] = v
    end
    return body
end

function ChatThread:dump()
    -- log:luaify_trace("ChatThread:dump", self.messages)
    -- log:luaify_trace("ChatThread:dump", self.last_request.response_messages)
    log:luaify_trace("ChatThread:dump", self)

    -- self:dump_raw_messages()
end

function ChatThread:dump_raw_messages()
    -- useful when need to see whitespace as-is and not \n\t

    local texts = { "ChatThread:dump" }
    for _, message in ipairs(self.messages) do
        table.insert(texts, message:dump_text())
    end
    log:info(table.concat(texts, "\n"))
end

return ChatThread
