local yanks = require("ask-openai.prediction.context.yanks")
local ctags = require("ask-openai.prediction.context.ctags")
-- local changelists = require("ask-openai.prediction.context.changelists")
-- local inspect = require("ask-openai.prediction.context.inspect")
local git_diff = require("ask-openai.prediction.context.git_diff")
local matching_ctags = require("ask-openai.prediction.context.matching_ctags")
local prompts = require("ask-openai.prediction.context.prompts")
local project = require("ask-openai.prediction.context.project")

---@alias IncludeToggles {
---  yanks: boolean,
---  commits: boolean,
---  ctags: boolean,
---  matching_ctags: boolean,
---  project: boolean
---  git_diff: boolean,
--- }

---@class CurrentContext
---
---@field yanks ContextItem
---@field commits ContextItem[]
---@field ctags ContextItem
---@field matching_ctags ContextItem
---@field project ContextItem
---
---@field includes IncludeToggles
---@field cleaned_prompt string
local CurrentContext = {}

---@return CurrentContext
function CurrentContext:items(prompt, always_include)
    local items = {}
    local includes = prompts.parse_includes(prompt)

    -- allow override to force include context items
    always_include = always_include or {}
    includes.yanks = includes.yanks or (always_include.yanks == true)
    includes.commits = includes.commits or (always_include.commits == true)
    includes.matching_ctags = includes.matching_ctags or (always_include.matching_ctags == true)
    includes.project = includes.project or (always_include.project == true)

    if includes.yanks then
        items.yanks = yanks.get_context_item()
    end
    if includes.commits then
        -- items.commits = git_diff.get_context_items()
    end
    -- if includes.ctags then
    --     items.ctags = ctags.get_context_items()
    -- end
    if includes.matching_ctags then
        items.matching_ctags = matching_ctags.get_context_item()
    end
    if includes.project then
        items.project = project.get_context_items()
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
    project.setup()
    -- changelists.setup()
    -- cocs.setup()
end

return CurrentContext
