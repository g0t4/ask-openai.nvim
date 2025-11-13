--- FYI MUST MIRROR OpeanAI format b/c this will get sent back
---   i.e. that means function is a nested object
---@class ToolCall : OpenAIChoiceDeltaToolCall
---@field id string
---@field index integer
---@field type integer
---@field function OpenAIChoiceDeltaToolCallFunction
---
---@field response_message table|nil -- TODO type this? is this the response message that had this tool call in it?
---@field response table|nil #mcp response TODO rename response is terrible name if it's the output of the tool call
local ToolCall = {}

---@return ToolCall
function ToolCall:new(o)
    o = o or {}
    o.id = o.id or ""
    setmetatable(o, self)
    self.__index = self
    return o
end

-- FYI marker interface for now

return ToolCall
