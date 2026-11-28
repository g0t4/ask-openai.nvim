local M = {}

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
