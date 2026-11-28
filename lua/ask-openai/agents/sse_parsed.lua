---@class SSEParsed
---@field sse_parsed LlamaServerSSEBase
local SSEParsed = {}

---@param sse_parsed LlamaServerSSEBase
---@return SSEParsed
function SSEParsed.new(sse_parsed)
    return setmetatable({ sse_parsed = sse_parsed }, { __index = SSEParsed })
end

---@return boolean
function SSEParsed:has_choices()
    return self.sse_parsed.choices ~= nil and #self.sse_parsed.choices > 0
end

---@return boolean
function SSEParsed:no_choices()
    return not self:has_choices()
end

return SSEParsed
