local eq = assert.are.same

describe("selection test", function()
    it("makes and retrieves a visual selection", function()
        vim.cmd("new")
        local bufnr = vim.api.nvim_get_current_buf()

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
            "line one",
            "line two",
            "line three",
        })

        -- Put cursor at start of what you wanna select
        vim.api.nvim_win_set_cursor(0, { 1, 5 }) -- line 1, col 5
        vim.cmd("normal! v") -- start visual mode

        print("notice no selection marks yet (b/c we are still in visual mode):")
        vim.api.nvim_win_set_cursor(0, { 2, 4 }) -- line 2, col 4
        vim.print("  '< is " .. vim.inspect(vim.fn.getcharpos("'<")))
        vim.print("  '> is " .. vim.inspect(vim.fn.getcharpos("'>")))

        -- *** YOU MUST EXIT VISUAL MODE TO CAPTURE marks for '< and '> (which is the last selection marks)
        vim.cmd("normal! v") -- exit visual mode (hit v a second time)
        --    FYI gv can re-select last selected region based on these marks

        print()
        print("now that we have exited, marks s/b set:")
        vim.print("  '< is " .. vim.inspect(vim.fn.getcharpos("'<")))
        vim.print("  '> is " .. vim.inspect(vim.fn.getcharpos("'>")))
        print()

        -- Yank the visual selection into register v
        vim.cmd([[normal! "vy]])
        selection_text = vim.fn.getreg("v")
        vim.print("selected text: '", selection_text, "'")
        eq("one\nline ", selection_text)
    end)
end)
