-- @class ChatThread
-- @see https://platform.openai.com/docs/api-reference/chat/create
-- @field messages ChatMessage[]
-- @field params ChatParams
-- @field last_request LastRequest
local ChatThread = {}

--- @param messages ChatMessage[]
--- @param params ChatParams
function ChatThread:new(messages, params)
    self = setmetatable({}, { __index = ChatThread })
    self.messages = messages or {}
    -- FYI think of params as the next request params
    self.params = params or {}
    -- if I want a history of requests I can build that separately
    self.last_request = nil
    return self
end

--- @param request LastRequest
function ChatThread:set_last_request(request)
    -- PRN consider moving this up a level to ctor as I would only need this the very first time..
    --  also maybe instead of using a body table I should start with a thread and pass that to curl_for
    -- request.thread = self -- TODO try this out
    self.last_request = request
end

--- @param message ChatMessage
function ChatThread:add_message(message)
    if not message.role then
        error("message.role is required")
    end
    if not message.content then
        error("message.content is required")
    end
    table.insert(self.messages, message)
end

--- build the body of a curl request!
---    taking into account all messages
----@return string JSON
function ChatThread:next_body()
    local body = {
        -- TODO deep clone messages?
        messages = self.messages,
    }
    -- merge params onto root of body:
    for k, v in pairs(self.params) do
        -- TODO deep clone, i.e. tools?
        body[k] = v
    end
    -- return body so it can be modified by backend (i.e. stream vs not)
    -- backend will serialize as is needed
    return body
end

return ChatThread
