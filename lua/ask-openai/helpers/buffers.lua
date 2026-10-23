local Selection = require("ask-openai.helpers.selection")
local M = {}

---@param bufnr? integer
---@return string
function M.get_text_in_buffer(bufnr)
    bufnr = bufnr or 0
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return table.concat(lines, "\n")
end

function M.dump_last_seletion_command()
    local selection = Selection.get_visual_selection_for_current_window()
    print(vim.inspect(selection))
end

function table_insert_split_lines(tbl, text)
    vim.list_extend(tbl, vim.split(text, "\n"))
end

return M
