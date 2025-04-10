require("ask-openai.prediction.context.inspect")

local M = {}

function M.get_change_list_with_lines()
    local bufnr = vim.api.nvim_get_current_buf()
    local result = vim.fn.getchangelist(bufnr) -- Retrieve change list
    local changelist = result[1] -- first is change list
    -- local position_in_list = result[2]
    -- todo don't take items after position in list?
    -- print("position: ", position_in_list)

    local changes = {}
    for _, change in ipairs(changelist) do
        local lnum = change.lnum
        if lnum ~= nil and changes[lnum] == nil then
            -- ensure only one inclusion of a given line, or allow dups?
            local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
            changes[lnum] = { lnum = lnum, col = change.col, line = line }
        end
    end
    return changes
end

function M.print_changes()
    local changes = M.get_change_list_with_lines()
    local lines_to_print = {}

    for _, change in pairs(changes) do
        table.insert(lines_to_print, string.format("Line %d, Column %d: %s", change.lnum, change.col, change.line))
    end

    print(table.concat(lines_to_print, "\n"))
end

function M.setup()
end

return M
