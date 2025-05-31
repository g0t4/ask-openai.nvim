require('ask-openai.helpers.testing')
local Selection = require('ask-openai.helpers.selection')
local should = require('devtools.tests.should')
local log = require("ask-openai.prediction.logger").predictions()
local busted = require("plenary.busted")
local before_each = busted.before_each
-- FYI useful way to find loaded modules (via globals)
-- vim.print(_G)


-- ***! methods to simulate a user selection:
--
-- *** marks are ONLY SET ON EXITING VISUAL MODE!!!
--
-- vim.cmd("normal! VV") -- works! (enter and exit)
--
-- vim.cmd("normal! V<Esc>") -- works! (enter and exit)
--
-- * set marks manually! good for testing too... especially for precise testing
-- vim.api.nvim_win_set_cursor(win, { 1, 2 }) -- line 3, col 2
-- vim.cmd("normal! m<")
-- vim.api.nvim_win_set_cursor(win, { 3, 4 }) -- line 2, col 4
-- vim.cmd("normal! m>")
--
-- ***! set precise mark positions
-- vim.fn.setcharpos("'<", { 0, 1, 2, 0 })
-- vim.fn.setcharpos("'>", { 0, 1, 4, 0 })
--
-- vim.print("current bufnr: " .. vim.api.nvim_get_current_buf())
-- vim.print("current win: " .. vim.api.nvim_get_current_win())
-- vim.print("'< is ", vim.fn.getcharpos("'<"))
-- vim.print("'> is ", vim.fn.getcharpos("'>"))

describe("get_visual_selection()", function()
    -- TODO! vet if issue w/ trailing char left after accept... is it in the selection logic

    local test_buffer_number = 0
    local function load_lines(lines)
        test_buffer_number = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(test_buffer_number, 0, -1, false, lines)

        local win = vim.api.nvim_open_win(test_buffer_number, true, {
            relative = 'editor',
            width = 80,
            height = 10,
            row = 0,
            col = 0,
            style = 'minimal',
        })
        vim.api.nvim_set_current_win(win)
        -- TODO do I need to set cursor initially before command?
        -- vim.api.nvim_win_set_cursor(win, { 1, 0 })
    end

    local function get_selection()
        return Selection.get_visual_selection_for_current_window()
    end


    describe("only one line", function()
        before_each(function()
            load_lines({ "foo the bar" })
        end)

        it("no selection is empty", function()
            -- nothing to do if its a new buffer/window
            -- vim.cmd("normal! <Esc>")
            local selection = get_selection()
            assert(selection:is_empty())
        end)

        it("one line selected, only one in buffer", function()
            vim.cmd('normal! VV') -- second V exits
            local selection = get_selection()
            should.be_equal("foo the bar", selection.original_text)
        end)

        it("middle of a line", function()
            vim.cmd('normal! 0wvw<Esc>') -- third V exits
            -- moves cursor to second word, then selects through one word (w)
            --   which results in the cursor on the third word,
            --   taking the first letter...
            --   which is interesting b/c my understanding is cursor is left of the char it visually sits on top of... maybe not in charwise?
            local selection = get_selection()
            should.be_equal("the b", selection.original_text)
        end)

        it("start of line (0) to end of line $", function()
            vim.cmd('normal! 0v$<Esc>')
            local selection = get_selection()
            should.be_equal("foo the bar", selection.original_text)
        end)

        -- it("end of a line with trailing newline", function()
        --     vim.cmd('normal! Vj') -- third V exits
        --     local selection = get_selection()
        --     should.be_equal("the bar\n", selection.original_text)
        --     end)
        -- end)

        -- describe("multiline", function()
        --     before_each(function()
        --         load_lines({ "foo the bar\n", "baz bat" })
        --     end)
    end)

    it("one line selected, subset of buffer", function()
    end)
    it("multiline selection, subset of buffer", function()
    end)
end)
