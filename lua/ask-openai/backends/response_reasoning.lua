local values = require("ask-openai.helpers.values")
local M = {}

-- Normalize backend field names without changing the raw response.
-- An explicit empty reasoning_content takes precedence over the fallback.
---@param delta table
---@return string|nil
function M.get_content(delta)
    -- TODO build a delta wrapper type to do this on the instance
    -- btw I verified all paths to this currently already use sse_wrapped and thus I don't need to check vim.NIL here
    return delta.reasoning_content or delta.reasoning
end

return M
