local M = {}

function M.split_lines(text)
    -- preserve empty lines too
    return vim.split(text, "\n")
end

return M
