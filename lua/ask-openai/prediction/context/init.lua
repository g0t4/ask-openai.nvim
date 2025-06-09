local yanks = require("ask-openai.prediction.context.yanks")
local ctags = require("ask-openai.prediction.context.ctags")
local changelists = require("ask-openai.prediction.context.changelists")
local inspect = require("ask-openai.prediction.context.inspect")
local cocs = require("ask-openai.prediction.context.cocs")

---@class CurrentContext
---@field yanks string
---@field edits string
local CurrentContext = {}

---@return CurrentContext
function CurrentContext:new()
    local instance = {
        yanks = yanks:get_prompt(),
        edits = "",
        ctags = ctags:get_prompt(),
    }
    setmetatable(instance, { __index = self })
    return instance
end

function CurrentContext.setup()
    yanks.setup()
    -- changelists.setup()
    -- cocs.setup()
end

return CurrentContext
