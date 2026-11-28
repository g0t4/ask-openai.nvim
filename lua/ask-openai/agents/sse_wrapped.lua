local values = require("ask-openai.helpers.values")

---@class SSEWrapped
---@field sse_parsed LlamaServerSSEBase
local SSEWrapped = {}

---@param sse_parsed LlamaServerSSEBase
---@return SSEWrapped
function SSEWrapped.new(sse_parsed)
    sse_parsed = values.nil_ify(sse_parsed) -- mutates in place
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

---@return boolean
function SSEWrapped:has_error()
    return self.sse_parsed.error ~= nil
end

---@return string?
function SSEWrapped:model()
    return self.sse_parsed.model
end

---@return string?
function SSEWrapped:finish_reason()
    local first_choice = self:first_choice()
    if first_choice == nil then
        return nil
    end
    return values.vim_NIL_to_nil(first_choice.finish_reason)
end

---@return boolean
function SSEWrapped:is_finished()
    return self:finish_reason() ~= nil
end

---@param message string
function SSEWrapped:log(message)
    local log = require("devtools.logs.logger").universal()
    log:info(message, self.sse_parsed)
end

return SSEWrapped
