local yanks = require("ask-openai.prediction.context.yanks")
local ctags = require("ask-openai.prediction.context.ctags")
local changelists = require("ask-openai.prediction.context.changelists")
local inspect = require("ask-openai.prediction.context.inspect")
local git_diff = require("ask-openai.prediction.context.git_diff")

---@class CurrentContext
---@field yanks string
---@field edits string
local CurrentContext = {}

---@return CurrentContext
function CurrentContext:new()
    local instance = {
        yanks = yanks:get_prompt(),
        edits = "",
        -- FYI just comment out to disable:
        -- ctags_files = ctags:get_ctag_files(),
        --   TODO how about target only currently imported files and their tags only... that would be tiny
        --    and maybe a list of require examples to make it easy to add a new import?
        --    OR, most frequently used tags? within the project
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
