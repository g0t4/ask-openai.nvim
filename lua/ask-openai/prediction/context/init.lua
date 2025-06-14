local yanks = require("ask-openai.prediction.context.yanks")
local ctags = require("ask-openai.prediction.context.ctags")
local changelists = require("ask-openai.prediction.context.changelists")
local inspect = require("ask-openai.prediction.context.inspect")
local git_diff = require("ask-openai.prediction.context.git_diff")
local matching_symbols = require("ask-openai.prediction.context.matching_symbols")


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

function CurrentContext:items()
    local items = {}
    table.insert(items, yanks.get_context_items())
    -- table.insert(items, changelists.get_context_items())
    table.insert(items, git_diff.get_context_items())
    -- table.insert(items, matching_symbols.get_context_items())
    -- table.insert(items, inspect.get_context_items())
    -- table.insert(items, ctags.get_context_items())
    return items
end

function CurrentContext.setup()
    yanks.setup()
    git_diff.setup()

    -- changelists.setup()
    -- cocs.setup()
end

return CurrentContext
