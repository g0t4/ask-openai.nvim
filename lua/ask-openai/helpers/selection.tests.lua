require('ask-openai.helpers.testing')
local Selection = require('ask-openai.helpers.selection')
local should = require('devtools.tests.should')
local log = require("ask-openai.logs.logger").predictions()

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
    describe("not in visual mode", function()
        ---@diagnostic disable-next-line: unused-function
        local function print_all_lines_troubleshoot()
            -- for testing only
            vim.print(vim.api.nvim_buf_get_lines(0, 0, -1, False))
        end

        before_each(function()
            load_lines({ "foo the bar" })
        end)

        it("no selections yet, should map to empty selection", function()
            -- nothing to do if its a new buffer/window
            local selection = get_selection()
            assert(selection:is_empty())
            assert(selection.original_text == '')
            should.be_equal("[r1,c1]-[r1,c1] 1-indexed (empty)", selection:range_str())
        end)

        it("single char-wise selection - minimum selection size is a single char - at first char, first line", function()
            vim.cmd(':0')
            vim.cmd('normal! 0vv') -- second v exits
            -- by the way, just enabling visual mode selects the current character (under cursor)
            local selection = get_selection()
            should.be_equal(selection.original_text, 'f')
            should.be_equal("[r1,c1]-[r1,c1] 1-indexed", selection:range_str())
        end)

        it("single char-wise selection - end of document, last char of last line", function()
            vim.cmd('normal! G$vv') -- second v exits
            -- G = last line, $ end of line, v = enable selection on last char of last line
            local selection = get_selection()
            should.be_equal(selection.original_text, 'r')
            should.be_equal("[r1,c11]-[r1,c11] 1-indexed", selection:range_str())
        end)

        it("one line selected, only one in buffer", function()
            vim.cmd('normal! VV') -- second V exits
            local selection = get_selection()
            should.be_equal("foo the bar", selection.original_text)
            should.be_equal("[r1,c1]-[r1,c11] 1-indexed", selection:range_str())
        end)

        it("linewise visual mode - selected last two lines thru end of file", function()
            load_lines({ "one", "two", "three", "four", "five" })

            vim.cmd(':4')
            vim.cmd(':normal! VjV') -- second V exits
            local selection = get_selection()
            should.be_equal("four\nfive", selection.original_text)
            should.be_equal("[r4,c1]-[r5,c4] 1-indexed", selection:range_str())
        end)

        it("linewise visual mode - selected first two lines - start of file", function()
            load_lines({ "one", "two", "three", "four", "five" })

            vim.cmd(':1')
            vim.cmd('normal! VjV') -- second V exits
            local selection = get_selection()
            should.be_equal("one\ntwo", selection.original_text)
            should.be_equal("[r1,c1]-[r2,c3] 1-indexed", selection:range_str())
        end)

        it("linewise visual mode - multiple lines selected in middle of buffer", function()
            load_lines({ "one", "two", "three", "four", "five" })

            vim.cmd(':2')
            vim.cmd('normal! V2jV') -- second V exits
            local selection = get_selection()
            should.be_equal("two\nthree\nfour", selection.original_text)
            should.be_equal("[r2,c1]-[r4,c4] 1-indexed", selection:range_str())
        end)


        it("middle of a line", function()
            vim.cmd('normal! 0wvwv') -- second v completes selection
            -- print_all_lines_troubleshoot()
            -- moves cursor to second word, then selects through one word (w)
            --   which results in the cursor on the third word,
            --   taking the first letter...
            --   which is interesting b/c my understanding is cursor is left of the char it visually sits on top of... maybe not in charwise?
            local selection = get_selection()
            should.be_equal("the b", selection.original_text)
            should.be_equal("[r1,c5]-[r1,c9] 1-indexed", selection:range_str())
        end)

        it("start of line with 0 to end of line with $", function()
            -- THIS IS not the same as Shift-V in terms of selecting...
            --   ... this is an exploratory test
            --   and indeed, the range is different!
            -- TODO figure out if this difference with \n at end of line has implications for selection replacement?
            --   and part of it is, $ goes thru the \n at the end of the line, whereas Shift-V doesn't select the \n on end (however it still pastes w/ a \n at end)
            vim.cmd('normal! 0v$v')
            local selection = get_selection()
            -- note the text I return does NOT include the \n...
            --  that could be my own logic or what I amdoing with with
            should.be_equal("foo the bar", selection.original_text)
            should.be_equal("[r1,c1]-[r1,c12] 1-indexed", selection:range_str())

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

    -- TODO split out these tests... I need a new wrapper around the low level methods I really never wanna touch ever again

    describe("still in visual mode", function()
        -- PRN if I want current mode checks, add these tests, though right now I don't think I have a direct need for these other than completeness of selection utility
        -- it("still in linewise 'V' visual mode - cursor position is AFTER other position", function()
        --     load_lines({ "one", "two", "three", "four", "five" })
        --     vim.cmd(':2')
        --     vim.cmd(':normal! Vj') -- STILL in V mode, so no 2nd V
        --     should.be_equal(vim.fn.mode(), "V")
        --
        --     local selection = get_selection()
        --     should.be_equal("two\nthree", selection.original_text)
        --     should.be_equal("[r2,c1]-[r3,c5] 1-indexed", selection:range_str())
        -- end)
        --
        -- it("still in linewise 'V' visual mode - cursor position is BEFORE other position", function()
        --     load_lines({ "one", "two", "three", "four", "five" })
        --     vim.cmd(':2')
        --     vim.cmd(':normal! Vk') -- STILL in V mode, so no 2nd V
        --     should.be_equal(vim.fn.mode(), "V")
        --
        --     local selection = get_selection()
        --     should.be_equal("two\nthree", selection.original_text)
        --     -- TODO should I have a diff selection type that only tracks lines b/c its a linewise selection object? makes more sense to me
        --     --    or use -1 for col of last line?
        --     should.be_equal("[11,c1]-[r2,c3] 1-indexed", selection:range_str())
        -- end)
        --
        -- -- TODO! still in charwise 'v' visual mode
        -- it("still in char-wise 'v' visual mode", function()
        --     load_lines({ "one", "two", "three", "four", "five" })
        --     vim.cmd(':2')
        --     vim.cmd(':normal! 0vj') -- STILL in v mode, so no 2nd v
        --     should.be_equal(vim.fn.mode(), "v")
        --
        --     local selection = get_selection()
        --     should.be_equal("two\nt", selection.original_text)
        --     should.be_equal("[r2,c1]-[r3,c1] 1-indexed", selection:range_str())
        -- end)
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
                should.be_equal("[r1,c1]-[r1,c10] 1-indexed", selection:range_str())
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
                should.be_equal("[r3,c1]-[r3,c25] 1-indexed", selection:range_str())
            end)

            it("single line selection, empty line", function()
                move_cursor_to_start_of_doc()
                vim.cmd('normal! GVV') -- second V exits
                local selection = get_selection()
                should.be_equal("line 14 the cow is over there", selection.original_text)
                should.be_equal("[r14,c1]-[r14,c29] 1-indexed", selection:range_str())
            end)
        end)

        describe("charwise", function()
            it("select 0$ with following line =>?? ", function()
                move_cursor_to_start_of_doc()
                vim.cmd('normal! v0$v') -- second v completes selection
                -- print_all_lines_troubleshoot()
                local selection = get_selection()
                should.be_equal("line 1 cow", selection.original_text)
                should.be_equal("[r1,c1]-[r1,c11] 1-indexed", selection:range_str())
                -- FYI original text does not have \n
                -- FYI and in this case we have the end_col > if we used Shift-V
            end)

            it("select end of line and start of next", function()
                -- row is 1-index, col is 0-index (when set cursor)
                local start_r1c6 = { 1, 5 } -- start on "1" in "line 1 cow"
                vim.api.nvim_win_set_cursor(0, start_r1c6)

                -- start charwise selection
                vim.cmd('normal! v3wv')

                -- print_all_lines_troubleshoot()

                local selection = get_selection()
                should.be_equal("1 cow\nline 2", selection.original_text)
                should.be_equal("[r1,c6]-[r2,c6] 1-indexed", selection:range_str())
            end)
        end)

        describe("set_selection_from_range", function()
            it("test it out", function()
                -- FTR... I am trying naming r\dc\d here instead of some sort of string parsing convenience method for setting position... which I could add but this is faster, use variable name
                -- FYI r\d+c\d+ is shown in 1-indexed numbers... hence I use the c6 here and 5 in the data... b/c the data needs to match for the nvim_win_set_cursor call
                local start_r1c6 = { 1, 5 } -- start on "1" in "line 1 cow"
                vim.api.nvim_win_set_cursor(0, start_r1c6)
                local end_r3c12 = { 3, 11 } -- end on "e" in first goose in "line 3 goose gooose goose"
                vim.api.nvim_win_set_cursor(0, end_r3c12)
                -- start charwise selection
                local resulting_selection = Selection.set_selection_from_range(start_r1c6, end_r3c12)
                should.be_equal("1 cow\nline 2 duck duck\nline 3 goose", resulting_selection.original_text)
                should.be_equal("[r1,c6]-[r3,c12] 1-indexed", resulting_selection:range_str())
            end)
        end)

        -- FYI it is not mission critical to even have failure tests of Ctrl-V, just a keep in mind if it helps later
        -- describe("Ctrl-V visual blockwise not supported", function()
        --     it("visual blockwise (Ctrl-V) not supported", function()
        --         vim.cmd('normal! <C-v>jj<C-v>') -- second v exits
        --         -- -- by the way, just enabling visual mode selects the current character (under cursor)
        --         -- \22 == visualmode() ?? why do I see empty then?
        --         local selection = get_selection()
        --         should.be_equal(selection.original_text, '')
        --         should.be_equal("[r1,c1]-[r1,c1] 1-indexed (empty)", selection:range_str())
        --     end)
        -- end)
    end)
end)

-- * can also use setcharpos... which is the mirror of what I use to read the positions
--  but this doesn't user actions, hence I prefer motions for testing (above)
-- vim.fn.setcharpos("'<", { 0, 1, 2, 0 })
-- vim.fn.setcharpos("'>", { 0, 1, 4, 0 })
-- vim.print("'< is ", vim.fn.getcharpos("'<"))
-- vim.print("'> is ", vim.fn.getcharpos("'>"))
