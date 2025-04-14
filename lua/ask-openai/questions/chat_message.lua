--- @class ChatMessage
--- @field role string
--- @field content string
--- @field tool_call_id string|nil
--- @field name string|nil
local ChatMessage = {}

function ChatMessage:new(role, content)
    self = setmetatable({}, { __index = ChatMessage })
    self.role = role
    self.content = content
    -- PRN enforce content is string here?
    return self
end

return ChatMessage
