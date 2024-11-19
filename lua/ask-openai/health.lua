local M = {}

function M.check()
    vim.health.start("ask-opeani report")
    require("ask-openai.config").check()
end

return M
