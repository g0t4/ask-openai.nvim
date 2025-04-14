---
-- @class ChatThread
-- @see https://platform.openai.com/docs/api-reference/chat/create
-- @field messages table
-- @field last_request string
local ChatThread = {}

function ChatThread:new()
    self = setmetatable({}, { __index = ChatThread })
    self.messages = {}
    self.last_request = nil
    return self
end

function ChatThread:set_last_request(request)
    self.last_request = request
end

function ChatThread:add_message(role, content)
    table.insert(self.messages, { role = role, content = content })
end

function ChatThread:to_json()
    local json_messages = {}
    for _, message in ipairs(self.messages) do
        table.insert(json_messages, { role = message.role, content = message.content })
    end
    return vim.fn.json_encode({ messages = json_messages })
end

return ChatThread
