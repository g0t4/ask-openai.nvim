local log = require('ask-openai.logs.logger').predictions()

--- see https://platform.openai.com/docs/api-reference/chat/create
---@class ChatThread
---@field messages TxChatMessage[]
---@field params ChatParams
---@field last_request LastRequest
---@field base_url string
local ChatThread = {}

---@param params ChatParams
---@param base_url string
---@return ChatThread
function ChatThread:new(params, base_url)
    self = setmetatable({}, { __index = ChatThread })
    self.messages = params.messages or {}
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

--- @param message TxChatMessage
function ChatThread:add_message(message)
    -- TODO drop previous messages => message.reasoning_content once a final message is detected?
    if not message.role then
        error("message.role is required")
    end
    table.insert(self.messages, message)
end

----@return table body
function ChatThread:next_curl_request_body()
    local body = {
        -- TODO! clone so I can manipulate messages sent back?
        messages = self.messages,
    }
    -- TODO! YES DROP THINKING HERE WHEN NO LONGER NEEDED (FOR ANY MESSAGE TYPE, NOT JUST gptoss Tool Calls in CoT
    -- merge params onto root of body:
    for k, v in pairs(self.params) do
        body[k] = v
    end
    return body
end

function ChatThread:dump()
    -- log:luaify_trace("last_request's RxAccumulatedMessages", self.last_request.accumulated_model_response_messages)
    -- log:luaify_trace("thread's TxChatMessages (history, sent on followup/toolresults)", self.messages)
    log:luaify_trace("ChatThread:dump", self)
end

return ChatThread
