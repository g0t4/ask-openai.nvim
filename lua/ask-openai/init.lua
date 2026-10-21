local M = {}

local config = require("ask-openai.config")
local log = require("devtools.logs.logger").universal()

function M.setup()
    config.setup()

    require("ask-openai.cmdline.suggest").setup()
    require("ask-openai.predictions.frontend").setup()
    require("ask-openai.frontends.context").setup()
    require("ask-openai.rewrites.frontend").setup()
    require("ask-openai.agents.frontend").setup()
    require("ask-openai.tools.mcp").setup()
    require("ask-openai.rag").setup()
    require("ask-openai.voiced").setup()
    require("ask-openai.clankerd").setup()
end

return M
