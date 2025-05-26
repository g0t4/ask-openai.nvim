local yanks = require("ask-openai.prediction.context.yanks")
local changelists = require("ask-openai.prediction.context.changelists")
local inspect = require("ask-openai.prediction.context.inspect")
local cocs = require("ask-openai.prediction.context.cocs")

local M = {}

-- @type Context
-- @field yanks string
-- @field edits string
function M:new()
    local instance = {
        yanks = yanks:get_prompt(),
        edits = {}
    }
    setmetatable(instance, { __index = self })
    return instance
end

function M.current_context()
    return M:new()
end

function M.setup()
    yanks.setup()
    changelists.setup()
    cocs.setup()
end

return M
