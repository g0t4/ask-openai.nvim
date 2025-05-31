require('ask-openai.helpers.testing')
local Selection = require('ask-openai.helpers.selection')
local should = require('devtools.tests.should')

describe("get_visual_selection()", function()
    -- TODO! get tests of this in place using plenary... with a real buffer
    -- TODO! vet if issue w/ trailing char left after accept... is it in the selection logic
    it("no selection is empty", function()
        local buffer_number = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buffer_number, 0, -1, false, { "a" })
        -- select current line using line-wise
        local selection = Selection._get_visual_selection(buffer_number)
        assert(selection:is_empty())
    end)


    describe("linewise", function()
        it("one line selected, only one in buffer", function()
            -- vim.execute [[execute 'normal! <M-v>']]
        end)
        it("one line selected, subset of buffer", function()
            -- vim.execute [[execute 'normal! <M-v>']]
        end)

        it("multiline selection, subset of buffer", function()
        end)
    end)
end)
