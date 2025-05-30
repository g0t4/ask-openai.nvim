---@class ChatMessage
---@field role string
---@field content string
---@field finish_reason string|nil
---@field tool_call_id string|nil
---@field name string|nil
---@field tool_calls ToolCall[]|nil
local ChatMessage = {}

--- FYI largely a marker interface as well, don't need to actually use this ctor
function ChatMessage:new(role, content)
    self = setmetatable({}, { __index = ChatMessage })
    self.role = role
    self.content = content
    self.finish_reason = nil
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

function ChatMessage:new_user_message(content)
    return ChatMessage:new("user", content)
end

function ChatMessage:new_assistant_message(content)
    return ChatMessage:new("assistant", content)
end

function ChatMessage:new_system_message(content)
    return ChatMessage:new("system", content)
end

function ChatMessage:add_tool_call_requests(call_request)
    if self.tool_calls == nil then
        self.tool_calls = {}
    end
    -- ONLY clone fields on the original call request from the model
    local new_call = {
        id = call_request.id,
        index = call_request.index,
        type = call_request.type,
        ["function"] = {
            name = call_request["function"].name,
            arguments = call_request["function"].arguments,
        }
    }
    table.insert(self.tool_calls, new_call)
end

return ChatMessage
