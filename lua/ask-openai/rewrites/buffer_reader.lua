---@class BufferReader
local M = {}

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

return M
