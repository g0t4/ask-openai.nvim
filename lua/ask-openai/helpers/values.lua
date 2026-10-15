local M = {}

---@param value string|vim.NIL|nil
---@return string
function M.empty_for_nil(value)
    if value == nil then
        return ""
    end
    if value == vim.NIL then
        return ""
    end
    ---@cast value string -- tell type checker to shut up
    return value
end

function M.vim_NIL_to_nil(value)
    if value == vim.NIL then
        return nil
    end
    return value
end

function M.nil_ify(value)
    if value == nil or value == vim.NIL then
        return nil
    end
    -- if table => go through key value pairs
    if type(value) == "table" then
        for key, val in pairs(value) do
            value[key] = M.nil_ify(val)
        end
    end

    return value
end

return M
