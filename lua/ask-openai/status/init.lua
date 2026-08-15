local M = {}
local lualine = require('ask-openai.status.lualine')

---@return table components
function M.get_lualine_components()
    return lualine.lualine_components()
end

return M
