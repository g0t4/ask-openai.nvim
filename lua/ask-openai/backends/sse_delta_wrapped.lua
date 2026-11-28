---@class ResponseReasoning
---@field delta table
local SSEDeltaWrapped = {}
SSEDeltaWrapped.__index = SSEDeltaWrapped

---@param delta table
---@return ResponseReasoning
function SSEDeltaWrapped.new(delta)
    return setmetatable({ delta = delta }, SSEDeltaWrapped)
end

-- TODO 2026-11-28 rest of helpers for wrapped content

---@return string|nil
function SSEDeltaWrapped:reasoning()
    return self.delta.reasoning_content or self.delta.reasoning
end

return SSEDeltaWrapped
