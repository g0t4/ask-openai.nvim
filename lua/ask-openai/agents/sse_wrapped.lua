---@class SSEWrapped
---@field sse_parsed LlamaServerSSEBase
local SSEWrapped = {}

---@param sse_parsed LlamaServerSSEBase
---@return SSEWrapped
function SSEWrapped.new(sse_parsed)
    return setmetatable({ sse_parsed = sse_parsed }, { __index = SSEWrapped })
end

---@return boolean
function SSEWrapped:has_choices()
    return self.sse_parsed.choices ~= nil and #self.sse_parsed.choices > 0
end

---@return LlamaServerChatCompletionSSE_Choice?
function SSEWrapped:first_choice()
    if self:no_choices() then
        return nil
    end
    return self.sse_parsed.choices[1]
end

---@return boolean
function SSEWrapped:no_choices()
    return not self:has_choices()
end

return SSEWrapped
