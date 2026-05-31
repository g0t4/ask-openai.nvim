--- Wrapper around unstructured tool call output (regardless of tool used)
---@class ToolCallOutput
---@field result any -- this is passed back to the model
---@field start_time_ms integer -- timestamp (ms) when tool execution began
---@field duration_ms integer -- duration in milliseconds (computed after tool completes)
local ToolCallOutput = {}

---@param o table|nil
---@return ToolCallOutput
function ToolCallOutput:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function ToolCallOutput:is_mcp()
    -- PRN what to use here?
    -- FYI perhaps I only need this logic if I am not wrapping all tools with a custom formatter (IMO not that likely that I wouldn't?)
    return self.result and self.result.content
end

return ToolCallOutput
