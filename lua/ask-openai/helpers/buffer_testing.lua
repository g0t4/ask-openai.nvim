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

describe("new_buffer_with_lines", function()
    -- a few tests to validate the above test helpers work correctly
    -- cool thing is, any test that imports this module will get these tests added too!

    it("sets lines", function()
        local bufnr = new_buffer_with_lines({ "line 1", "line 2", "line 3", "line 4" })

        local line1 = vim.fn.getbufoneline(bufnr, 1)
        assert.equal("line 1", line1)

        local line4 = vim.fn.getbufoneline(bufnr, 4)
        assert.equal("line 4", line4)

        --  don't turn this into a test of getbufoneline/getbufline
        assert.equal("", vim.fn.getbufoneline(bufnr, 5))
        assert.equal("", vim.fn.getbufoneline(bufnr, 10))
    end)
end)
