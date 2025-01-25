local M = {}

function M.check()
    vim.health.start("ask-opeani report")
    require("ask-openai.config").check()
    -- TODO predictions config? other scenario tests (validate backends, if scenarios are enabled?)
end

return M
