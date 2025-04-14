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

function ChatMessage:new_tool_response(content, tool_call_id, name)
    self = ChatMessage:new("tool", content)
    --PRN enforce strings are not empty?
    self.tool_call_id = tool_call_id
    self.name = name
    return self
end

return ChatMessage
