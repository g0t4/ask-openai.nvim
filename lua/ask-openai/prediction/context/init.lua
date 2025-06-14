local yanks = require("ask-openai.prediction.context.yanks")
-- local ctags = require("ask-openai.prediction.context.ctags")
-- local changelists = require("ask-openai.prediction.context.changelists")
-- local inspect = require("ask-openai.prediction.context.inspect")
local git_diff = require("ask-openai.prediction.context.git_diff")
-- local matching_symbols = require("ask-openai.prediction.context.matching_symbols")
local prompts = require("ask-openai.prediction.context.prompts")

---@class CurrentContext
---@field yanks ContextItem
---@field commits ContextItem[]
---@field includes { yanks: boolean?, commits: boolean?, [string]: any }
---@field cleaned_prompt string
local CurrentContext = {}

---@return CurrentContext
function CurrentContext:items(prompt, always_includes)
    local items = {}
    local includes = prompts.parse_includes(prompt)

    -- allow override to force include context items
    always_includes = always_includes or {}
    includes.yanks = includes.yanks or (always_includes.yanks == true)
    includes.commits = includes.commits or (always_includes.commits == true)

    if includes.yanks then
        items.yanks = yanks.get_context_item()
    end
    if includes.commits then
        items.commits = git_diff.get_context_items()
    end
    -- table.insert(items, changelists.get_context_items())
    -- table.insert(items, matching_symbols.get_context_items())
    -- table.insert(items, inspect.get_context_items())
    -- table.insert(items, ctags.get_context_items())
    items.includes = includes
    items.cleaned_prompt = includes.cleaned_prompt
    return items
end

function CurrentContext.setup()
    yanks.setup()
    git_diff.setup()

    -- changelists.setup()
    -- cocs.setup()
end

return CurrentContext
