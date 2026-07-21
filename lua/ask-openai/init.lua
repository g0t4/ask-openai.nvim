local M = {}

local config = require("ask-openai.config")
local log = require("devtools.logs.logger").universal()

---@param user_options? AskOpenAIOptions
function M.setup(user_options)
    if user_options ~= nil then
        vim.notify("user_options are discontinued for now", vim.log.levels.WARN)
        log:warn("user_options are discontinued for now, you passed:", user_options)
    end
    config.setup()

    require("ask-openai.cmdline.suggest").setup()
    require("ask-openai.predictions.frontend").setup()
    require("ask-openai.frontends.context").setup()
    require("ask-openai.rewrites.frontend").setup()
    require("ask-openai.agents.frontend").setup()
    require("ask-openai.tools.mcp").setup()
    require("ask-openai.rag").setup()
end

return M
