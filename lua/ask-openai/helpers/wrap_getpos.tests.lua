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
                should.be_equal(2, sel.start_line_b1)
                should.be_equal(1, sel.start_col_b1)
                should.be_equal(3, sel.end_line_b1)
                should.be_equal(1, sel.end_col_b1)
            end)
            it("cursor at start of linewise selection - same as reverse", function()
                load_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! 0Vk')
                should.be_equal(vim.fn.mode(), "V")

                local sel = GetPos.SelectionRange_Line1Col1()
                should.be_equal(2, sel.start_line_b1)
                should.be_equal(1, sel.start_col_b1)
                should.be_equal(3, sel.end_line_b1)
                should.be_equal(1, sel.end_col_b1)
            end)
            it("cursor at start of linewise selection - same as reverse", function()
                load_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! 0V')
                should.be_equal(vim.fn.mode(), "V")

                local sel = GetPos.SelectionRange_Line1Col1()
                -- FYI start_line=end_line, start_col=end_col for single line selection
                should.be_equal(3, sel.start_line_b1)
                should.be_equal(1, sel.start_col_b1)
                should.be_equal(3, sel.end_line_b1)
                should.be_equal(1, sel.end_col_b1)
            end)
            it("cursor at start of linewise selection - same as reverse", function()
                load_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! 0Vj')
                should.be_equal(vim.fn.mode(), "V")

                local sel = GetPos.SelectionRange_Line1Col1()
                -- FYI start_line=end_line, start_col=end_col for single line selection
                -- nice thing about be_same and hash => shows sorted keys in output diff view
                should.be_same({
                    start_line_b1 = 3,
                    end_line_b1 = 4,
                    start_col_b1 = 1,
                    end_col_b1 = 1
                }, sel)

                vim.cmd(":normal! 2l") -- move 2 chars right (only changes col of end position
                sel = GetPos.SelectionRange_Line1Col1()
                -- should.be_equal(3, sel.end_col_b1)
                should.be_same({
                    start_line_b1 = 3,
                    end_line_b1 = 4,
                    start_col_b1 = 1,
                    end_col_b1 = 3
                }, sel)
            end)
        end)
    end)
end)
