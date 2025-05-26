local yanks = require("ask-openai.prediction.context.yanks")
local changelists = require("ask-openai.prediction.context.changelists")
local inspect = require("ask-openai.prediction.context.inspect")
local cocs = require("ask-openai.prediction.context.cocs")

---@class CurrentContext
---@field yanks string
---@field edits string
local CurrentContext = {}

function CurrentContext:new()
    local instance = {
        yanks = yanks:get_prompt(),
        edits = "",
    }
    setmetatable(instance, { __index = self })
    return instance
end

function CurrentContext.current_context()
    return CurrentContext:new()
end

function CurrentContext.setup()
    yanks.setup()
    changelists.setup()
    cocs.setup()
end

return CurrentContext
