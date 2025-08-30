require('ask-openai.helpers.testing')
local Selection = require('ask-openai.helpers.selection')
local should = require('devtools.tests.should')
local log = require("ask-openai.logs.logger").predictions()
require('ask-openai.helpers.wrap_tests')
require('ask-openai.helpers.wrap_getpos')


-- TODO split out these tests... I need a new wrapper around the low level methods I really never wanna touch ever again
describe("GetPos wrappers", function()
    -- PRN incorporate settings for obscure details (when the need arises):
    --   :h * selection
    --   :h * virtualedit=all - position cursor past actual characters (i.e. g$ - end of screen line)

    it("LastSelection", function()
        it("selection was closed", function()
            it("cursor was at END of linewise selection", function()
                load_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':2')
                vim.cmd(':normal! 0VjV') -- select this line and next
                should.be_equal(vim.fn.mode(), "n")

                local sel = GetPos.LastSelection()
                should.be_same_diff({
                    start_line_b1 = 2,
                    end_line_b1   = 3,
                    start_col_b1  = 1,
                    end_col_b1    = 2147483647,
                }, sel)
            end)

            it("cursor was at START of linewise selection", function()
                load_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! VkV') -- select this line and line above
                should.be_equal(vim.fn.mode(), "n")
                local sel = GetPos.LastSelection()
                should.be_same_diff({
                    start_line_b1 = 2,
                    end_line_b1   = 3,
                    start_col_b1  = 1,
                    end_col_b1    = 2147483647, -- this is fine actually... since I am in line wise mode anyways... col is meaningless
                }, sel)
            end)


            it("cursor was at START of charwise selection - on same line", function()
                load_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':2')
                vim.cmd(':normal! 0v2lv') -- two chars right
                should.be_equal(vim.fn.mode(), "n")
                local sel = GetPos.LastSelection()
                should.be_same_diff({
                    start_line_b1 = 2,
                    end_line_b1   = 2,
                    start_col_b1  = 1,
                    end_col_b1    = 3,
                }, sel)
            end)
            it("cursor was at END of charwise selection - on same line", function()
                load_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! $v2hv') -- two chars left (from end of line)
                should.be_equal(vim.fn.mode(), "n")
                local sel = GetPos.LastSelection()
                should.be_same_diff({
                    start_line_b1 = 3,
                    end_line_b1   = 3,
                    start_col_b1  = 3,
                    end_col_b1    = 5,
                }, sel)
            end)

            it("cursor was at START OF charwise selection - across two lines - start at end of longer line", function()
                load_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! $vjv') -- 2j = down two lines
                should.be_equal(vim.fn.mode(), "n")
                local sel = GetPos.LastSelection()
                should.be_same_diff({
                    start_line_b1 = 3,
                    end_line_b1   = 4,
                    start_col_b1  = 5, -- line 3 has 5 chars (thre[e])
                    end_col_b1    = 5, -- ?? line 4 only has 4 chars but still b/c I was in col 5 I am still in it on line 4 after down
                }, sel)
            end)
            it("cursor was at END of charwise selection - across two lines", function()
            end)
        end)
    end)

    it("SelectionRange_Line1Col1", function()
        it("still selected", function()
            -- FYI this is probably rare to happen... I really should just close the mode and thus capture into '< and '>
            it("cursor at end of linewise selection - same as reverse", function()
                load_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':2')
                vim.cmd(':normal! 0Vj') -- 0 = start of line, then V select and j=down a line
                should.be_equal(vim.fn.mode(), "V")

                -- TODO remove this lower level test? should I also remove the API for it
                local line_base1, col_base1 = GetPos.CursorPosition_Line1Col1()
                should.be_equal(3, line_base1)
                should.be_equal(1, col_base1)

                local sel = GetPos.SelectionRange_Line1Col1()
                local expected = {
                    start_line_b1 = 2,
                    start_col_b1  = 1,
                    end_line_b1   = 3,
                    end_col_b1    = 1,
                }
                should.be_same_diff(expected, sel)
            end)

            it("cursor at start of linewise selection - same as reverse", function()
                load_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! 0Vk')
                should.be_equal(vim.fn.mode(), "V")

                local sel = GetPos.SelectionRange_Line1Col1()
                should.be_same_diff({
                    start_line_b1 = 2,
                    start_col_b1  = 1,
                    end_line_b1   = 3,
                    end_col_b1    = 1,
                }, sel)
            end)
            it("cursor at start of linewise selection - same as reverse", function()
                load_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! 0V')
                should.be_equal(vim.fn.mode(), "V")

                local sel = GetPos.SelectionRange_Line1Col1()
                -- FYI start_line=end_line, start_col=end_col for single line selection
                should.be_same_diff({
                    start_line_b1 = 3,
                    start_col_b1  = 1,
                    end_line_b1   = 3,
                    end_col_b1    = 1,
                }, sel)
            end)
            it("cursor at start of linewise selection - same as reverse", function()
                load_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! 0Vj')
                should.be_equal(vim.fn.mode(), "V")

                local sel = GetPos.SelectionRange_Line1Col1()
                -- FYI start_line=end_line, start_col=end_col for single line selection
                -- nice thing about be_same and hash => shows sorted keys in output diff view
                should.be_same_diff({
                    start_line_b1 = 3,
                    end_line_b1 = 4,
                    start_col_b1 = 1,
                    end_col_b1 = 1
                }, sel)

                -- * move 2 chars right on second line, just tests how col works in linewise visual selection
                vim.cmd(":normal! 2l") -- move 2 chars right (only changes col of end position
                sel = GetPos.SelectionRange_Line1Col1()
                -- should.be_equal(3, sel.end_col_b1)
                should.be_same_diff({
                    start_line_b1 = 3,
                    end_line_b1 = 4,
                    start_col_b1 = 1,
                    end_col_b1 = 3
                }, sel)
            end)
        end)
    end)
end)
