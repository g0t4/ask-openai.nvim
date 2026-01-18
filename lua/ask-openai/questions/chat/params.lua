---@class ChatParams
---@field model string
---@field stream boolean|nil
---@field messages TxChatMessage[]
---
--- TODO validate these are correct:
---@field temperature number|nil
---@field top_p number|nil
---@field n number|nil
---@field stop string[]|nil
---@field max_tokens number|nil
---@field presence_penalty number|nil
---@field frequency_penalty number|nil
---@field tools table[]|nil
--- TODO MORE
local ChatParams = {}

-- FYI mostly use this as a marker interface and put it on hash-lik tables that I new up w/o this ctor
function ChatParams:new(params)
    -- no reason to use this ctor until I have some logic here (i.e. validate)
    self = setmetatable(params, { __index = ChatParams })
    return self
end

return ChatParams
