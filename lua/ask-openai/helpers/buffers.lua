local Selection = require("ask-openai.helpers.selection")
local M = {}

function M.get_current_buffer_entire_text()
    -- PRN take buffer_number
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    return table.concat(lines, "\n")
end

function M.dump_last_seletion()
    local selection = Selection.get_visual_selection()
    print(vim.inspect(selection))
end

function table_insert_many(tbl, items)
    for _, item in ipairs(items) do
        table.insert(tbl, item)
    end
end

function table_insert_split_lines(tbl, text)
    table_insert_many(tbl, vim.split(text, "\n"))
end

return M
