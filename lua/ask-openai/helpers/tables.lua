local M = {}

--- shallow copy only copies the top-level table "container"
--- keys are copied w/ respective values, but values are not copied (use vim.deep_copy for that)
--- works with both list tables and maps
---@param tbl table?
---@return table
function M.shallow_copy(tbl)
    if not tbl then
        return {}
    end
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = v
    end
    setmetatable(copy, getmetatable(tbl))
    return copy
end

return M
