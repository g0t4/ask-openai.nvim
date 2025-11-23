require('ask-openai.helpers.testing')
local Selection = require('ask-openai.helpers.selection')
local should = require('devtools.tests.should')
local log = require("ask-openai.logs.logger").predictions()
require('ask-openai.helpers.buffer_testing')
local GetPos = require('ask-openai.helpers.wrap_getpos')
local _describe = require('devtools.tests._describe')

function ignore(a, b)
end

only = it
-- it = ignore -- uncomment to run "only" tests, otherwise, comment out to run all again (regardless if marked only/it)


-- TODO split out these tests... I need a new wrapper around the low level methods I really never wanna touch ever again
_describe("GetPos wrappers", function()
    -- PRN incorporate settings for obscure details (when the need arises):
    --   :h * selection
    --   :h * virtualedit=all - position cursor past actual characters (i.e. g$ - end of screen line)

    _describe("edge case - no selection yet", function()
        new_buffer_with_lines({ "one", "two", "three", "four", "five" })
        vim.cmd(':1')
        vim.cmd('normal! 0l') -- move one char from start of line
        should.be_equal(vim.fn.mode(), "n")

        it("LastSelection is all zeros", function()
            local selection = GetPos.LastSelection()
            should.be_same_colorful_diff({
                start_line_b1    = 0,
                end_line_b1      = 0,
                start_col_b1     = 0,
                end_col_b1       = 0,
                mode             = "n",
                last_visual_mode = "",
                linewise         = false,
            }, selection)
        end)

        it("CurrentSelection() returns coords of cursor for both start and end positions", function()
            local sel = GetPos.CurrentSelection()
            should.be_same_colorful_diff({
                start_line_b1    = 1,
                end_line_b1      = 1,
                start_col_b1     = 2,
                end_col_b1       = 2,
                mode             = "n",
                last_visual_mode = "",
                linewise         = false,
            }, sel)
        end)
    end)

    _describe("LastSelection", function()
        -- TODO! what about when I don't make any selection before calling LastSelection?
        --   it will work but I should add some verification around what it's doing and make sure it is what I want

        _describe("selection was closed", function()
            it("cursor was at END of linewise selection", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':2')
                vim.cmd(':normal! 0VjV') -- select this line and next
                should.be_equal(vim.fn.mode(), "n")

                local sel = GetPos.LastSelection()
                should.be_same_colorful_diff({
                    start_line_b1    = 2,
                    end_line_b1      = 3,
                    start_col_b1     = 1,
                    end_col_b1       = 2147483647,
                    mode             = "n",
                    last_visual_mode = "V",
                    linewise         = true,
                }, sel)
            end)

            it("cursor was at START of linewise selection", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! VkV') -- select this line and line above
                should.be_equal(vim.fn.mode(), "n")
                local sel = GetPos.LastSelection()
                should.be_same_colorful_diff({
                    start_line_b1    = 2,
                    end_line_b1      = 3,
                    start_col_b1     = 1,
                    -- TODO map to -1 for end col (aka end of line)... in fact that works in many test cases
                    --   TODO OR map cols to nil when in V visual linewise mode?
                    end_col_b1       = 2147483647, -- this is fine actually... since I am in line wise mode anyways... col is meaningless
                    mode             = "n",
                    last_visual_mode = "V",
                    linewise         = true,
                }, sel)
            end)


            it("cursor was at START of charwise selection - on same line", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':2')
                vim.cmd(':normal! 0v2lv') -- two chars right
                should.be_equal(vim.fn.mode(), "n")
                local sel = GetPos.LastSelection()
                should.be_same_colorful_diff({
                    start_line_b1    = 2,
                    end_line_b1      = 2,
                    start_col_b1     = 1,
                    end_col_b1       = 3,
                    mode             = "n",
                    last_visual_mode = "v",
                    linewise         = false,
                }, sel)
            end)
            it("cursor was at END of charwise selection - on same line", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! $v2hv') -- two chars left (from end of line)
                should.be_equal(vim.fn.mode(), "n")
                local sel = GetPos.LastSelection()
                should.be_same_colorful_diff({
                    start_line_b1    = 3,
                    end_line_b1      = 3,
                    start_col_b1     = 3,
                    end_col_b1       = 5,
                    mode             = "n",
                    last_visual_mode = "v",
                    linewise         = false,
                }, sel)
            end)
            it("cursor was at END of charwise selection - across two lines - start at start of first", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! 0vjv')
                should.be_equal(vim.fn.mode(), "n")
                local sel = GetPos.LastSelection()
                should.be_same_colorful_diff({
                    start_line_b1    = 3,
                    end_line_b1      = 4,
                    start_col_b1     = 1,
                    end_col_b1       = 1, -- started on col 1 so still on it in next row
                    mode             = "n",
                    last_visual_mode = "v",
                    linewise         = false,
                }, sel)
            end)

            it("cursor was at END of charwise selection - across two lines - start at end of longer line", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! $vjv') -- 2j = down two lines
                should.be_equal(vim.fn.mode(), "n")
                local sel = GetPos.LastSelection()
                should.be_same_colorful_diff({
                    start_line_b1    = 3,
                    end_line_b1      = 4,
                    start_col_b1     = 5, -- line 3 has 5 chars (thre[e])
                    end_col_b1       = 5, -- ?? line 4 only has 4 chars but still b/c I was in col 5 I am still in it on line 4 after down
                    mode             = "n",
                    last_visual_mode = "v",
                    linewise         = false,
                }, sel)
            end)

            it("cursor was at END of charwise selection - across two lines", function()
            end)
        end)
    end)

    _describe("CurrentSelection", function()
        _describe("still selected", function()
            -- FYI this is probably rare to happen... I really should just close the mode and thus capture into '< and '>
            it("cursor at end of linewise selection - same as reverse", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':2')
                vim.cmd(':normal! 0Vj') -- 0 = start of line, then V select and j=down a line
                should.be_equal(vim.fn.mode(), "V")

                -- TODO remove this lower level test? should I also remove the API for it
                local cursor_pos = GetPos.CursorPosition()
                local expected_pos = {
                    line_b1 = 3,
                    col_b1  = 1,
                }
                should.be_same_colorful_diff(expected_pos, cursor_pos)

                local sel = GetPos.CurrentSelection()
                local expected = {
                    start_line_b1    = 2,
                    start_col_b1     = 1,
                    end_line_b1      = 3,
                    end_col_b1       = 1,
                    mode             = "V",
                    last_visual_mode = "",
                    linewise         = true,
                }
                should.be_same_colorful_diff(expected, sel)
            end)

            it("cursor at start of linewise selection - same as reverse", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! 0Vk')
                should.be_equal(vim.fn.mode(), "V")

                local sel = GetPos.CurrentSelection()
                should.be_same_colorful_diff({
                    start_line_b1    = 2,
                    start_col_b1     = 1,
                    end_line_b1      = 3,
                    end_col_b1       = 1,
                    mode             = "V",
                    last_visual_mode = "",
                    linewise         = true,
                }, sel)
            end)
            it("cursor at start of linewise selection - same as reverse", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! 0V')
                should.be_equal(vim.fn.mode(), "V")

                local sel = GetPos.CurrentSelection()
                -- FYI start_line=end_line, start_col=end_col for single line selection
                should.be_same_colorful_diff({
                    start_line_b1    = 3,
                    start_col_b1     = 1,
                    end_line_b1      = 3,
                    end_col_b1       = 1,
                    mode             = "V",
                    last_visual_mode = "",
                    linewise         = true,
                }, sel)
            end)
            it("cursor at start of linewise selection - same as reverse", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':3')
                vim.cmd(':normal! 0Vj')
                should.be_equal(vim.fn.mode(), "V")

                local sel = GetPos.CurrentSelection()
                -- FYI start_line=end_line, start_col=end_col for single line selection
                -- nice thing about be_same and hash => shows sorted keys in output diff view
                should.be_same_colorful_diff({
                    start_line_b1    = 3,
                    end_line_b1      = 4,
                    start_col_b1     = 1,
                    end_col_b1       = 1,
                    mode             = "V",
                    last_visual_mode = "",
                    linewise         = true,
                }, sel)

                -- * move 2 chars right on second line, just tests how col works in linewise visual selection
                vim.cmd(":normal! 2l") -- move 2 chars right (only changes col of end position
                sel = GetPos.CurrentSelection()
                -- should.be_equal(3, sel.end_col_b1)
                should.be_same_colorful_diff({
                    start_line_b1    = 3,
                    end_line_b1      = 4,
                    start_col_b1     = 1,
                    end_col_b1       = 3,
                    mode             = "V",
                    last_visual_mode = "",
                    linewise         = true,
                }, sel)
            end)
        end)

        _describe("still selected after previous selection too", function()
            it("first is linewise V one line, then charwise two l (2 chars right)", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(':2')
                vim.cmd(':normal! 0VV') -- single linewise, in and out
                should.be_equal(vim.fn.mode(), "n")
                vim.cmd(':4')
                vim.cmd(':normal! 0vl') -- charise, 2 chars
                should.be_equal(vim.fn.mode(), "v")

                local sel = GetPos.CurrentSelection()
                local expected = {
                    start_line_b1    = 4,
                    start_col_b1     = 1,
                    end_line_b1      = 4,
                    end_col_b1       = 2,
                    mode             = "v", -- currently in a selection
                    last_visual_mode = "V", -- last selection was V... but doesn't  matter b/c we are currently selecting in v! and when its done it'll become last_visualmode
                    linewise         = false,
                }
                should.be_same_colorful_diff(expected, sel)
            end)
        end)
    end)
end)


_describe("GetPosSelectionRange", function()
    it(":new(range) uses range object fields", function()
        local range = {
            start_line_b1 = 1,
            start_col_b1  = 2,
            end_line_b1   = 3,
            end_col_b1    = 4,
            -- TODO others? I don't know if these should be on the wrapper type or not?
            -- mode             = mode,
            -- last_visual_mode = last_visual_mode,
            -- linewise         = linewise,
        }

        local instance = GetPosSelectionRange:new(range)

        assert.not_equal(instance, GetPosSelectionRange, ":new() should return a new instance")
        local instance_metatable = getmetatable(instance)
        assert.not_equal(instance_metatable, nil, "instance should have a defined metatable")
        assert.equal(instance_metatable.__index, GetPosSelectionRange, "instance should inherit behavior from GetPosSelectionRange")
        assert.equal(instance.start_line_b1, 1)
        assert.equal(instance.start_col_b1, 2)
        assert.equal(instance.end_line_b1, 3)
        assert.equal(instance.end_col_b1, 4)


        -- TODO! FINISH THE TEST CASE HERE... I passed out instead of continuing this...
        --   BTW I am using this in my code notes plugin idea and other parts of dotfiles repo
    end)

    _describe("check return types", function()
        _describe("start of selection is before end", function()
            it("GetPos.CurrentSelection() returns GetPosSelectionRange", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd("normal Vj") -- make a selection (one line)

                local instance = GetPos.CurrentSelection()
                -- vim.print(instance)

                assert.not_nil(getmetatable(instance))
                assert.equal(getmetatable(instance).__index, GetPosSelectionRange)
            end)
        end)

        _describe("end of selection is before start (aka reversed)", function()
            it("GetPos.CurrentSelection() returns GetPosSelectionRange", function()
                new_buffer_with_lines({ "one", "two", "three", "four", "five" })
                vim.cmd(":3") -- make a selection (one line)
                vim.cmd("normal Vk") -- reverse search

                local instance = GetPos.CurrentSelection()
                -- vim.print(instance)

                assert.not_nil(getmetatable(instance))
                assert.equal(getmetatable(instance).__index, GetPosSelectionRange)
            end)
        end)

        it("GetPos.LastSelection() returns GetPosSelectionRange", function()
            new_buffer_with_lines({ "one", "two", "three", "four", "five" })
            vim.cmd("normal Vj") -- make a selection (one line)
            vim.cmd("normal <esc>") -- stop selection (so it becomes LastSelection)

            local instance = GetPos.LastSelection()
            -- vim.print(instance)

            assert.not_nil(getmetatable(instance))
            assert.equal(getmetatable(instance).__index, GetPosSelectionRange)
        end)
    end)

    it(":line_count() returns number of lines the selection spans, without considering column offsets within each line", function()
        local selection = GetPosSelectionRange:new({
            start_line_b1 = 1,
            -- start_col_b1 = ,
            end_line_b1 = 3,
            -- end_col_b1 = ,
        })

        assert.equal(selection:line_count(), 3)
    end)

    describe("base0() methods", function()
        local selection = GetPosSelectionRange:new({
            start_line_b1 = 10,
            end_line_b1 = 20,
            start_col_b1 = 30,
            end_col_b1 = 40,
        })

        it(":start_line_b0()", function()
            assert.equal(selection:start_line_b0(), 9)
        end)
        it(":end_line_b0()", function()
            assert.equal(selection:end_line_b0(), 19)
        end)
        it(":start_col_b0()", function()
            assert.equal(selection:start_col_b0(), 29)
        end)
        it(":end_col_b0()", function()
            assert.equal(selection:end_col_b0(), 39)
        end)
    end)
end)
