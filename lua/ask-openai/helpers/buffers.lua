local Selection = require("ask-openai.helpers.selection")
local M = {}

function M.get_current_buffer_entire_text()
    -- PRN take buffer_number
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    return table.concat(lines, "\n")
end

---@return table<string, string>
function M.all()
    local result = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_option(bufnr, "buflisted") then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name == "" then name = tostring(bufnr) end
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            result[name] = table.concat(lines, "\n")
        end
    end
    return result
end

function M.dump_last_seletion()
    local selection = Selection.get_visual_selection_for_current_window()
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
