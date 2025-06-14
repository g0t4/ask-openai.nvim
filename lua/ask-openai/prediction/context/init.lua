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

function parse_includes(prompt)
    local include = {
        yanks = false,
        commits = false,
    }
    local include_all = (prompt == nil) or (prompt:gmatch("/all") ~= nil)
    if include_all then
        include.yanks = true
        include.commits = true
    else
        include.yanks = (prompt:gmatch("/yank") ~= nil)
        include.commits = (prompt:gmatch("/commits") ~= nil)
    end
    return include
end

function CurrentContext:items(prompt)
    local items = {}
    local include = parse_includes(prompt)
    if include.yanks then
        table.insert(items, yanks.get_context_items())
    end
    if include.commits then
        table.insert(items, git_diff.get_context_items())
    end
    -- table.insert(items, changelists.get_context_items())
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
