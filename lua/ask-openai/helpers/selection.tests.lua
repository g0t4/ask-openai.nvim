require('ask-openai.helpers.testing')
local Selection = require('ask-openai.helpers.selection')
local should = require('devtools.tests.should')

describe("get_visual_selection()", function()
    -- TODO! vet if issue w/ trailing char left after accept... is it in the selection logic

    local test_buffer_number = 0
    local function buffer_has_lines(lines)
        test_buffer_number = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(test_buffer_number, 0, -1, false, lines)
    end

    local function get_selection()
        return Selection._get_visual_selection(test_buffer_number)
    end

    describe("linewise", function()
        describe("only one line", function()
            it("no selection is empty", function()
                buffer_has_lines({ "foo the bar" })
                local selection = get_selection()
                assert(selection:is_empty())
            end)

            it("one line selected, only one in buffer", function()
                buffer_has_lines({ "foo the bar" })
                local selection = get_selection()
                -- local expected = { start_row = 1, end_row = 2 }
                -- should.equal(selection, expected)


                -- vim.execute [[execute 'normal! <M-v>']]
            end)
            it("one line selected, subset of buffer", function()
                -- vim.execute [[execute 'normal! <M-v>']]
            end)
        end)

        it("multiline selection, subset of buffer", function()
        end)
    end)
end)
