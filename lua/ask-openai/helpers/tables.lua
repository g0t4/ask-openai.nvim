local M = {}

--- shallow copy only copies the top-level table "container"
--- keys are copied w/ respective values, but values are not copied (use vim.deep_copy for that)
--- works with both list tables and maps
function M.shallow_copy_table(tbl)
    -- TODO add some tests if this causes trouble
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
