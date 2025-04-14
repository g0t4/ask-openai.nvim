-- @class ChatThread
-- @see https://platform.openai.com/docs/api-reference/chat/create
-- @field messages ChatMessage[]
-- @field last_request LastRequest
local ChatThread = {}

function ChatThread:new()
    self = setmetatable({}, { __index = ChatThread })
    self.messages = {}
    self.last_request = nil
    return self
end

--- @param request LastRequest
function ChatThread:set_last_request(request)
    -- TODO need to extract new messages from request? or should I pass messages and return a request object?
    -- TODO? request.thread = self  -- two way reference to thread from request too?
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

function ChatThread:to_json()
    -- TODO use this? or get rid of it... a way to serialize all messages?
    local json_messages = {}
    for _, message in ipairs(self.messages) do
        table.insert(json_messages, { role = message.role, content = message.content })
    end
    return vim.fn.json_encode({ messages = json_messages })
end

return ChatThread
