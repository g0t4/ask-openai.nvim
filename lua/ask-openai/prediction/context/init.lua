local yanks = require("ask-openai.prediction.context.yanks")
local changelists = require("ask-openai.prediction.context.changelists")
local inspect = require("ask-openai.prediction.context.inspect")
local cocs = require("ask-openai.prediction.context.cocs")

local M = {}

function M.current_context()
    -- TODO classify this ctx object and use it as type hint in consumer code
    local ctx = {
        -- TODO have each context type build its own prompt and pass that back here
        yanks = yanks.get_prompt(),
        edits = {}, -- TODO
    }
    return ctx
end

function M.setup()
    yanks.setup()
    changelists.setup()
    cocs.setup()
end

return M
