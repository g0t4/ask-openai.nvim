--- FYI MUST MIRROR OpeanAI format b/c this will get sent back
---   i.e. that means function is a nested object
---@class ToolCall : OpenAIChoiceDeltaToolCall
---@field id string
---@field index integer
---@field type integer
---@field function OpenAIChoiceDeltaToolCallFunction
---
---@field response_message table|nil -- TODO type this? response message to send call results back to the model that will, also attached to chat_thread (history)
---@field call_output? ToolCallOutput -- tool call outputs (specific to a given tool type, some have standard structure, i.e. MCP)
local ToolCall = {}

---@return ToolCall
function ToolCall:new(o)
    o = o or {}
    o.id = o.id or ""
    setmetatable(o, self)
    self.__index = self
    return o
end

---@return boolean
function ToolCall:is_done()
    -- FYI see run_tool_calls_for_the_model() for when call_output is set
    return self.call_output ~= nil
end

-- FYI marker interface for now

return ToolCall
