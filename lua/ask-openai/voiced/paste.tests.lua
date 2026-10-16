-- testing modules:
require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require 'luassert'
local should = require('devtools.tests.should')
local describe = require('devtools.tests.describe')
local buffers = require('devtools.tests.buffers')
-- system under test:
local paste = require('ask-openai.voiced.paste')

local function get_lines(bufnr)
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

describe("voiced.paste", function()
    after_each(function()
        paste.cancel()
    end)

    describe("arm", function()
        it("captures the current window's buffer and cursor", function()
            local bufnr = buffers.new_buffer_with_lines({ "alpha", "beta", "gamma" })
            vim.api.nvim_win_set_cursor(0, { 2, 1 }) -- line 2 (base1), col 1 (base0)

            assert.is_true(paste.arm())
            assert.is_true(paste.is_armed())

            paste.paste("X")
            -- inserted "X" at line_base0=1, col_base0=1 => "beta" -> "bXeta"
            should.be_same({ "alpha", "bXeta", "gamma" }, get_lines(bufnr))
        end)

    end)

    describe("paste", function()
        it("inserts text at the captured cursor position", function()
            local bufnr = buffers.new_buffer_with_lines({ "alpha", "beta", "gamma" })
            vim.api.nvim_win_set_cursor(0, { 2, 0 }) -- line 2, col 0
            paste.arm()

            assert.is_true(paste.paste("hello"))
            should.be_same({ "alpha", "hellobeta", "gamma" }, get_lines(bufnr))
        end)

        it("moves the cursor to the end of the inserted text", function()
            buffers.new_buffer_with_lines({ "alpha", "beta", "gamma" })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            paste.arm()

            paste.paste("hello")
            local cursor = vim.api.nvim_win_get_cursor(0)
            -- line 2 (base1), col = #"hello" = 5
            should.be_same({ 2, 5 }, cursor)
        end)

        it("handles multiline text", function()
            local bufnr = buffers.new_buffer_with_lines({ "alpha", "beta" })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            paste.arm()

            paste.paste("line one\nline two")
            -- multiline: "line one" replaces the start of line 2, "line two" is a
            -- new line with the remainder of the original line appended.
            should.be_same({ "alpha", "line one", "line twobeta" }, get_lines(bufnr))
            -- cursor ends after "line two" (col 8) on the new last line
            local cursor = vim.api.nvim_win_get_cursor(0)
            should.be_same({ 3, 8 }, cursor)
        end)

        it("is one-shot: disarms after a successful paste", function()
            local bufnr = buffers.new_buffer_with_lines({ "alpha", "beta" })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            paste.arm()

            assert.is_true(paste.paste("first"))
            assert.is_false(paste.is_armed())
            assert.is_false(paste.paste("second")) -- disarmed, so no-op
            should.be_same({ "alpha", "firstbeta" }, get_lines(bufnr))
        end)

        it("returns false when not armed", function()
            assert.is_false(paste.paste("nope"))
        end)

        it("returns false when the target buffer is invalid", function()
            local win_id = vim.api.nvim_get_current_win()
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b" })
            vim.api.nvim_win_set_buf(win_id, bufnr)
            paste.arm()
            vim.api.nvim_buf_delete(bufnr, { force = true })

            assert.is_false(paste.paste("nope"))
        end)
    end)

    describe("cancel", function()
        it("disarms without pasting", function()
            local bufnr = buffers.new_buffer_with_lines({ "alpha", "beta" })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            paste.arm()
            assert.is_true(paste.is_armed())

            paste.cancel()
            assert.is_false(paste.is_armed())
            assert.is_false(paste.paste("nope"))
            should.be_same({ "alpha", "beta" }, get_lines(bufnr))
        end)
    end)
end)
