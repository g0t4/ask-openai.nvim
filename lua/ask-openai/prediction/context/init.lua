local yanks = require("ask-openai.prediction.context.yanks")
local ctags = require("ask-openai.prediction.context.ctags")
-- local changelists = require("ask-openai.prediction.context.changelists")
-- local inspect = require("ask-openai.prediction.context.inspect")
local git_diff = require("ask-openai.prediction.context.git_diff")
local matching_ctags = require("ask-openai.prediction.context.matching_ctags")
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
    -- if includes.ctags then
    --     items.ctags = ctags.get_context_items()
    -- end
    if includes.matching_ctags then
        items.matching_ctags = matching_ctags.get_context_item()
    end

    items.includes = includes
    items.cleaned_prompt = includes.cleaned_prompt
    return items
end

function CurrentContext.setup()
    yanks.setup()
    git_diff.setup()
    ctags.setup()
    matching_ctags.setup()
    -- changelists.setup()
    -- cocs.setup()
end

return CurrentContext
