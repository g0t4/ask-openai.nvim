local M = {}

-- PRN use this as base for ChatWindow?

function M.open_float(lines, opts)
    opts = opts or {}
    opts.width = opts.width or 0.6
    opts.height = opts.height or 0.6

    -- create a scratch buffer
    local buf = vim.api.nvim_create_buf(false, true) -- nofile, scratch

    -- fill the buffer
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    -- calculate size/position
    local columns = vim.o.columns

    local lines_opt = vim.o.lines
    local width = math.floor(columns * opts.width)
    local height = math.floor(lines_opt * opts.height)
    local row = opts.row or math.floor((lines_opt - height) / 2) - 1
    local col = opts.col or math.floor((columns - width) / 2)

    -- open the floating window
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = opts.border or "rounded",
    })

    return buf, win
end

return M
