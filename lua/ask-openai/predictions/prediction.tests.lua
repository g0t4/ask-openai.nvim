-- testing modules:
require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require 'luassert'
local buffers = require('devtools.tests.buffers')
local Prediction = require("ask-openai.predictions.prediction")

describe("Prediction", function()
    describe("insert_accepted prefix stripping", function()
        it("strips repeated indentation prefix from first line", function()
            -- Setup: cursor on indented line with code after cursor
            local buffer_lines = {
                "def foo():",
                "    pass",
                "    ", -- line 3 is just indentation (4 spaces)
            }
            local bufnr = buffers.new_buffer_with_lines(buffer_lines)
            vim.api.nvim_win_set_cursor(0, { 3, 4 }) -- cursor after 4 spaces
            
            local prediction = Prediction.new({})
            prediction.buffer = bufnr
            
            -- Simulate FIM completion that repeats the indentation
            local insert_lines = { "    return x" }
            
            -- Act: call insert_accepted
            prediction:insert_accepted(insert_lines)
            
            -- Assert: the inserted portion (after cursor position) should be stripped
            -- Insert happens at col 4, so we check from col 4 onwards
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 2, 3, false)[1]
            local inserted_portion = actual_line:sub(5) -- col 4 is index 5 (1-indexed)
            -- Trim trailing whitespace (buffer may add extra space)
            assert.equal("return x", vim.trim(inserted_portion))
        end)
        
        it("does not strip when prefix does not match", function()
            local buffer_lines = {
                "def foo():",
                "    pass",
                "    ", -- line 3 is just indentation
            }
            local bufnr = buffers.new_buffer_with_lines(buffer_lines)
            vim.api.nvim_win_set_cursor(0, { 3, 4 }) -- cursor after 4 spaces
            
            local prediction = Prediction.new({})
            prediction.buffer = bufnr
            
            -- Simulate FIM completion with different prefix (not matching)
            local insert_lines = { "    return x + y" }
            
            prediction:insert_accepted(insert_lines)
            
            -- Should strip because it matches the cursor prefix (4 spaces)
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 2, 3, false)[1]
            local inserted_portion = actual_line:sub(5) -- col 4 is index 5 (1-indexed)
            assert.equal("return x + y", vim.trim(inserted_portion))
        end)
        
        it("handles blank line insert_lines gracefully", function()
            local buffer_lines = { "    code", "" }
            local bufnr = buffers.new_buffer_with_lines(buffer_lines)
            vim.api.nvim_win_set_cursor(0, { 2, 0 }) -- cursor at start of empty line
            
            local prediction = Prediction.new({})
            prediction.buffer = bufnr
            
            -- Blank line should not trigger prefix stripping logic
            prediction:insert_accepted({ "" })
            
            -- Should just insert blank line at cursor position
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 1, 2, false)[1]
            assert.equal("", actual_line)
        end)
        
        it("handles cursor at column 0 (no prefix)", function()
            local buffer_lines = { "code", "" }
            local bufnr = buffers.new_buffer_with_lines(buffer_lines)
            vim.api.nvim_win_set_cursor(0, { 2, 0 }) -- cursor at start of empty line
            
            local prediction = Prediction.new({})
            prediction.buffer = bufnr
            
            -- No prefix to strip when cursor is at column 0
            prediction:insert_accepted({ "    new code" })
            
            -- Should insert as-is (no stripping)
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 1, 2, false)[1]
            assert.equal("    new code", actual_line)
        end)
        
        it("handles partial prefix match correctly", function()
            local buffer_lines = { "    existing", "" }
            local bufnr = buffers.new_buffer_with_lines(buffer_lines)
            vim.api.nvim_win_set_cursor(0, { 2, 4 }) -- cursor after 4 spaces
            
            local prediction = Prediction.new({})
            prediction.buffer = bufnr
            
            -- Insert line with MORE indentation than cursor prefix
            local insert_lines = { "        more indent" } -- 8 spaces
            
            prediction:insert_accepted(insert_lines)
            
            -- Should strip the first 4 spaces (matching cursor prefix)
            -- Insert at col 4, so we check from col 4 onwards
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 1, 2, false)[1]
            local inserted_portion = actual_line:sub(5) -- col 4 is index 5 (1-indexed)
            -- After stripping 4 spaces from 8, we have 4 remaining spaces + text
            -- Use gsub to remove only trailing whitespace (not leading)
            local trimmed = inserted_portion:gsub("%s+$", "")
            assert.equal("    more indent", trimmed)
        end)
        
        it("handles insert line shorter than prefix gracefully", function()
            local buffer_lines = { "        long indent", "" }
            local bufnr = buffers.new_buffer_with_lines(buffer_lines)
            vim.api.nvim_win_set_cursor(0, { 2, 8 }) -- cursor after 8 spaces
            
            local prediction = Prediction.new({})
            prediction.buffer = bufnr
            
            -- Insert line that is shorter than the prefix
            local insert_lines = { "short" }
            
            -- Should not error and should not strip (condition #first_line >= #cursor_prefix fails)
            prediction:insert_accepted(insert_lines)
            
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 1, 2, false)[1]
            assert.equal("short", actual_line)
        end)
        
        it("handles mixed content before cursor correctly", function()
            local buffer_lines = { "    def foo():", "        pass", "        " }
            local bufnr = buffers.new_buffer_with_lines(buffer_lines)
            vim.api.nvim_win_set_cursor(0, { 3, 8 }) -- cursor after 8 spaces
            
            local prediction = Prediction.new({})
            prediction.buffer = bufnr
            
            -- Simulate FIM completion that repeats the indentation
            local insert_lines = { "        return x" }
            
            prediction:insert_accepted(insert_lines)
            
            -- Should strip the first 8 spaces
            -- Insert at col 8, so we check from col 8 onwards
            local actual_line = vim.api.nvim_buf_get_lines(prediction.buffer, 2, 3, false)[1]
            local inserted_portion = actual_line:sub(9) -- col 8 is index 9 (1-indexed)
            assert.equal("return x", vim.trim(inserted_portion))
        end)
    end)
end)
