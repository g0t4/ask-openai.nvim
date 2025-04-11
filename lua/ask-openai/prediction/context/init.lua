local yanks = require("ask-openai.prediction.context.yanks")
local changelists = require("ask-openai.prediction.context.changelists")
local inspect = require("ask-openai.prediction.context.inspect")
local cocs = require("ask-openai.prediction.context.cocs")

local M = {}

function M.current_context()
    local ctx = {
        yanks = yanks.get(),
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
