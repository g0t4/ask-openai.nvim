function new_buffer_with_lines(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    local win = vim.api.nvim_open_win(bufnr, true, {
        relative = 'editor',
        width = 80,
        height = 10,
        row = 0,
        col = 0,
        style = 'minimal',
    })
    vim.api.nvim_set_current_win(win)
    return bufnr
    -- FYI not setting cursor before commands, let the tests handle reliably setting cursor
    -- vim.api.nvim_win_set_cursor(win, { 1, 0 })
end
