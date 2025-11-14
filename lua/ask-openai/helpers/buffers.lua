local Selection = require("ask-openai.helpers.selection")
local M = {}

---@param bufnr? integer
---@return string
function M.get_current_buffer_entire_text(bufnr)
    bufnr = bufnr or 0
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return table.concat(lines, "\n")
end

---@return table<string, string>
function M.get_entire_text_of_all_buffers()
    -- TODO use w/ /open_files slash command (or remove this)
    local text_by_file = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_option(bufnr, "buflisted") then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name == "" then name = tostring(bufnr) end
            text_by_file[name] = M.get_current_buffer_entire_text(bufnr)
        end
    end
    return text_by_file
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
