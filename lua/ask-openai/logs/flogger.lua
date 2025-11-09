local M = {}

-- TODO this is unused, try it out
-- MERGE it into logger as .flog(...)

function M.flog(fmt)
    local info = debug.getinfo(2, "f")
    local i, vars = 1, {}
    while true do
        local name, value = debug.getlocal(2, i)
        if not name then break end
        vars[name] = value
        i = i + 1
    end

    -- replace {var} with var=value
    local msg = fmt:gsub("{(.-)}", function(key)
        local val = vars[key]
        if val == nil then
            return key .. "=nil"
        elseif type(val) == "table" then
            return key .. "=" .. vim.inspect(val)
        else
            return key .. "=" .. tostring(val)
        end
    end)

    -- replace this with your own logger call
    print(msg)
end

return M
