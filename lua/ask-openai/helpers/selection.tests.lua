require('ask-openai.helpers.testing')
local Selection = require('ask-openai.helpers.selection')
local should = require('devtools.tests.should')
local log = require("ask-openai.prediction.logger").predictions()


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


-- examples for testing selection methods
--foo the bar
-- baz boo doo

describe("get_visual_selection()", function()
    describe("edge case hunting - only one line", function()
        before_each(function()
            load_lines({ "foo the bar" })
        end)

        it("no selection => is empty", function()
            -- nothing to do if its a new buffer/window
            -- vim.cmd("normal! <Esc>")
            local selection = get_selection()
            assert(selection:is_empty())
            assert(selection.original_text == '')
            should.be_equal("[r1,c1]-[r1,c1] (empty)", selection:range_str())
        end)

        it("one line selected, only one in buffer", function()
            vim.cmd('normal! VV') -- second V exits
            local selection = get_selection()
            should.be_equal("foo the bar", selection.original_text)
            should.be_equal("[r1,c1]-[r1,c11]", selection:range_str())
        end)

        it("middle of a line", function()
            vim.cmd('normal! 0wvw<Esc>') -- third V exits
            -- moves cursor to second word, then selects through one word (w)
            --   which results in the cursor on the third word,
            --   taking the first letter...
            --   which is interesting b/c my understanding is cursor is left of the char it visually sits on top of... maybe not in charwise?
            local selection = get_selection()
            should.be_equal("the b", selection.original_text)
            should.be_equal("[r1,c5]-[r1,c9]", selection:range_str())
        end)

        it("start of line with 0 to end of line with $", function()
            -- THIS IS not the same as Shift-V in terms of selecting...
            --   ... this is an exploratory test
            --   and indeed, the range is different!
            -- TODO figure out if this difference with \n at end of line has implications for selection replacement?
            --   and part of it is, $ goes thru the \n at the end of the line, whereas Shift-V doesn't select the \n on end (however it still pastes w/ a \n at end)
            vim.cmd('normal! 0v$<Esc>')
            local selection = get_selection()
            -- note the text I return does NOT include the \n...
            --  that could be my own logic or what I amdoing with with
            should.be_equal("foo the bar", selection.original_text)
            should.be_equal("[r1,c1]-[r1,c12]", selection:range_str())

            -- PRN revisit later... too much for now, I need to do more exciting things... btw this is a contraction of the selection range around \n which is not the bug I've encountered that I wanna fix... and now with the selection tests being pretty robust... seems like it would have to be smth in the replace logic that has a bug
            -- -- OK THIS IS WEIRD... gv => yank doesn't copy the \n on the end?!
            -- --   this is in part b/c yank doesn't wait for marks to be set, IIUC... it happens before marks are set? and so it has different behavior to determine what is selected?
            -- vim.cmd('normal! gv"vy') -- copy selection to register v... I wanna check original_text matches the the selection is yanked as a double check
            -- local yanked = vim.fn.getreg("v")
            -- should.be_equal("foo the bar", yanked)
        end)

        -- TODO! do I want to add some tests to cover what using getcharpos accomplishes for me?
        -- * getcharpos also resolves the issue with v:maxcol as the returned col number (i.e. in visual line mode selection)
        -- I should do some high level tests so I could swap out getcharpos if needed?
    end)

    local function move_cursor_to_start_of_doc()
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
    end

    describe("multi line", function()
        before_each(function()
            local lines = {
                "line 1 cow",
                "line 2 duck duck",
                "line 3 goose gooose goose",
                "line 4 goose",
                "", -- 5
                "line 6 storm the gates",
                "line 7 stormy weather",
                "", -- 8
                "lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer posuere erat a ante.", -- 9
                "Lorem ipsum dolor sit amet, consectetur adipiscing elit.", -- 10
                "Integer posuere erat a ante", -- 11
                "", -- 12
                "line 13",
                "line 14 the cow is over there",
            }
            load_lines(lines)
        end)

        describe("linewise selections", function()
            it("single line selection, first line", function()
                move_cursor_to_start_of_doc()
                vim.cmd('normal! VV') -- second V exits
                local selection = get_selection()
                should.be_equal("line 1 cow", selection.original_text)

                -- TODO add verification of selection offsets for other critical test cases, this should help find the issue w/ trailing character bug
                should.be_equal("[r1,c1]-[r1,c10]", selection:range_str())
                -- *** when the ranges don't match, plenary shows string diff (stacked) and it all lines up SUPER USEFUL! i.e.:
                -- Passed in:
                -- (string) '[r1,c1]-[r1,c10]'
                -- Expected:
                -- (string) '[r1,c1]-[r1,c11]'
            end)

            it("single line selection, middle of document", function()
                move_cursor_to_start_of_doc()
                vim.cmd('normal! 2jVV') -- second V exits
                local selection = get_selection()
                should.be_equal("line 3 goose gooose goose", selection.original_text)
                should.be_equal("[r3,c1]-[r3,c25]", selection:range_str())
            end)

            it("single line selection, empty line", function()
                move_cursor_to_start_of_doc()
                vim.cmd('normal! GVV') -- second V exits
                local selection = get_selection()
                should.be_equal("line 14 the cow is over there", selection.original_text)
                should.be_equal("[r14,c1]-[r14,c29]", selection:range_str())
            end)
        end)

        describe("multiline selection, subset of buffer", function()

        end)
    end)
end)
