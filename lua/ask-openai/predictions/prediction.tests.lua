-- testing modules:
require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require 'luassert'
local buffers = require('devtools.tests.buffers')
local Prediction = require("ask-openai.predictions.prediction")

describe("Prediction", function()
    local function create_test_prediction(buffer_lines, cursor_line_base1, cursor_col_base0)
        local bufnr = buffers.new_buffer_with_lines(buffer_lines)
        vim.api.nvim_win_set_cursor(0, { cursor_line_base1, cursor_col_base0 })
        
        local prediction = Prediction.new({})
        prediction.buffer = bufnr
        return prediction
    end
    
    describe("insert_accepted", function()
        it("strips repeated indentation prefix from first line", function()
            -- Setup: cursor on indented line with code after cursor
            local buffer_lines = {
                "def foo():",
                "    pass",
                "    # cursor here -> '    '",
            }
            local prediction = create_test_prediction(buffer_lines, 3, 4) -- cursor at col 4 (after 4 spaces)
            
            -- Simulate FIM completion that repeats the indentation
            local insert_lines = { "    return x" }
            
            -- Act: call insert_accepted
            prediction:insert_accepted(insert_lines)
            
            -- Assert: the inserted line should have the prefix stripped
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 2, 3, false)[1]
            assert.equal("return x", actual_line)
        end)
        
        it("does not strip when prefix does not match", function()
            local buffer_lines = {
                "def foo():",
                "    pass",
                "    # cursor here -> '    '",
            }
            local prediction = create_test_prediction(buffer_lines, 3, 4)
            
            -- Simulate FIM completion with different prefix (not matching)
            local insert_lines = { "    return x + y" }
            
            prediction:insert_accepted(insert_lines)
            
            -- Should still strip because it matches the cursor prefix (4 spaces)
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 2, 3, false)[1]
            assert.equal("return x + y", actual_line)
        end)
        
        it("handles empty insert_lines gracefully", function()
            local buffer_lines = { "line1", "line2" }
            local prediction = create_test_prediction(buffer_lines, 2, 0)
            
            -- Should not error on empty table
            prediction:insert_accepted({})
            
            -- Buffer should be unchanged (nothing inserted)
            assert.equal(2, #vim.api.nvim_buf_get_lines(prediction.buffer, 0, -1, false))
        end)
        
        it("handles blank line insert_lines gracefully", function()
            local buffer_lines = { "    code", "" }
            local prediction = create_test_prediction(buffer_lines, 2, 0)
            
            -- Blank line should not trigger prefix stripping logic
            prediction:insert_accepted({ "" })
            
            -- Should just insert blank line
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 1, 2, false)[1]
            assert.equal("", actual_line)
        end)
        
        it("handles cursor at column 0 (no prefix)", function()
            local buffer_lines = { "code", "" }
            local prediction = create_test_prediction(buffer_lines, 2, 0)
            
            -- No prefix to strip when cursor is at column 0
            prediction:insert_accepted({ "    new code" })
            
            -- Should insert as-is (no stripping)
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 1, 2, false)[1]
            assert.equal("    new code", actual_line)
        end)
        
        it("handles partial prefix match correctly", function()
            local buffer_lines = { "    existing", "" }
            local prediction = create_test_prediction(buffer_lines, 2, 4) -- cursor after 4 spaces
            
            -- Insert line with MORE indentation than cursor prefix
            local insert_lines = { "        more indent" }
            
            prediction:insert_accepted(insert_lines)
            
            -- Should strip the first 4 spaces (matching cursor prefix)
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 1, 2, false)[1]
            assert.equal("    more indent", actual_line)
        end)
        
        it("handles insert line shorter than prefix gracefully", function()
            local buffer_lines = { "        long indent", "" }
            local prediction = create_test_prediction(buffer_lines, 2, 8) -- cursor after 8 spaces
            
            -- Insert line that is shorter than the prefix
            local insert_lines = { "short" }
            
            -- Should not error and should not strip (condition #first_line >= #cursor_prefix fails)
            prediction:insert_accepted(insert_lines)
            
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 1, 2, false)[1]
            assert.equal("short", actual_line)
        end)
    end)
end)
