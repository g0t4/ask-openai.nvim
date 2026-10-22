local values = require("ask-openai.helpers.values")
local M = {}

-- Normalize backend field names without changing the raw response.
-- An explicit empty reasoning_content takes precedence over the fallback.
---@param delta table
---@return string|nil
function M.get_content(delta)
    return values.vim_NIL_to_nil(delta.reasoning_content)
        or values.vim_NIL_to_nil(delta.reasoning)
end

return M
