-- testing modules:
require("ask-openai.helpers.test_setup").modify_package_path()
local should = require('devtools.tests.should')
local describe = require('devtools.tests.define.describe')
local test_buffers = require('devtools.tests.buffers')
-- system under test:
local BufferController = require('ask-openai.agents.viewer.buffers')
local Fold = require('ask-openai.agents.viewer.fold')
local LinesBuilder = require('ask-openai.agents.viewer.lines_builder')

--- Create a fresh BufferController backed by a new test buffer with the given lines.
---@param lines string[]
---@return BufferController
local function new_buffer_controller_with_lines(lines)
    local bufnr = test_buffers.new_buffer_with_lines(lines)
    return BufferController:new(bufnr)
end

--- Build a LinesBuilder preloaded with the given lines (no marks/folds).
---@param lines string[]
---@return LinesBuilder
local function new_lines_builder(lines)
    local builder = LinesBuilder:new(vim.api.nvim_create_namespace("buffers_test"))
    builder:append_lines(lines)
    return builder
end

describe("BufferController:get_lines_from", function()
    describe("start at first line (0)", function()
        it("returns every line joined by \\n", function()
            local controller = new_buffer_controller_with_lines({ "one", "two", "three" })
            should.be_equal("one\ntwo\nthree", controller:get_lines_from(0))
        end)

        it("single line buffer", function()
            local controller = new_buffer_controller_with_lines({ "only" })
            should.be_equal("only", controller:get_lines_from(0))
        end)
    end)

    describe("start in the middle", function()
        it("returns all lines from that point onward", function()
            local controller = new_buffer_controller_with_lines({ "one", "two", "three", "four" })
            should.be_equal("three\nfour", controller:get_lines_from(2))
        end)
    end)

    describe("start at last line", function()
        it("returns only the last line", function()
            local controller = new_buffer_controller_with_lines({ "one", "two", "three" })
            should.be_equal("three", controller:get_lines_from(2))
        end)
    end)

    describe("start at or beyond end of buffer", function()
        it("returns empty string when index equals line count", function()
            local controller = new_buffer_controller_with_lines({ "one", "two" })
            should.be_equal("", controller:get_lines_from(2))
        end)

        it("returns empty string when index is far beyond line count", function()
            local controller = new_buffer_controller_with_lines({ "one", "two" })
            should.be_equal("", controller:get_lines_from(10))
        end)
    end)

    describe("empty buffer", function()
        it("returns empty string", function()
            local controller = new_buffer_controller_with_lines({})
            should.be_equal("", controller:get_lines_from(0))
        end)
    end)

    describe("blank lines preserved", function()
        it("keeps blank lines in the result", function()
            local controller = new_buffer_controller_with_lines({ "one", "", "two", "", "three" })
            should.be_equal("\ntwo\n\nthree", controller:get_lines_from(1))
        end)
    end)
end)

describe("BufferController:get_line_count", function()
    describe("fresh buffer always has the phantom empty first line", function()
        it("nvim_create_buf", function()
            -- make sure the phantom line is not due to new_buffer_controller_with_lines
            local bufnr = vim.api.nvim_create_buf(false, true)
            local controller = BufferController:new(bufnr)
            should.be_equal(1, controller:get_line_count())
        end)

        it("new_buffer_controller_with_lines", function()
            -- show that phantom line happens from this way too
            local controller = new_buffer_controller_with_lines({})
            should.be_equal(1, controller:get_line_count())
        end)
    end)

    it("counts appended lines", function()
        local controller = new_buffer_controller_with_lines({})
        controller:append_styled_lines(new_lines_builder({ "one", "two", "three" }))
        should.be_equal(3, controller:get_line_count())
    end)
end)

describe("BufferController:clear", function()
    it("empties a populated buffer", function()
        local controller = new_buffer_controller_with_lines({ "one", "two" })
        controller:clear()
        should.be_equal("", controller:get_lines_from(0))
        should.be_equal(1, controller:get_line_count())
    end)

    it("is a no-op on an already-empty buffer", function()
        local controller = new_buffer_controller_with_lines({})
        controller:clear()
        should.be_equal("", controller:get_lines_from(0))
        should.be_equal(1, controller:get_line_count())
    end)
end)

describe("BufferController:append_styled_lines", function()
    it("first append on a fresh buffer replaces the phantom empty first line (starts at line 0)", function()
        local controller = new_buffer_controller_with_lines({})
        controller:append_styled_lines(new_lines_builder({ "one", "two" }))
        should.be_equal("one\ntwo", controller:get_lines_from(0))
    end)

    it("second append on a fresh buffer appends after the first, not replacing it", function()
        local controller = new_buffer_controller_with_lines({})
        controller:append_styled_lines(new_lines_builder({ "one", "two" }))
        controller:append_styled_lines(new_lines_builder({ "three" }))
        should.be_equal("one\ntwo\nthree", controller:get_lines_from(0))
    end)

    it("append to a pre-populated buffer goes after existing content", function()
        -- this feels duplicative (leave it for now) in that it is in part testing the behavior of new_buffer_with_lines
        local controller = new_buffer_controller_with_lines({ "alpha", "beta" })
        controller:append_styled_lines(new_lines_builder({ "one", "two" }))
        should.be_equal("alpha\nbeta\none\ntwo", controller:get_lines_from(0))
    end)

    it("append of an empty builder leaves a single empty line", function()
        local controller = new_buffer_controller_with_lines({})
        controller:append_styled_lines(new_lines_builder({}))
        should.be_equal("", controller:get_lines_from(0))
        should.be_equal(1, controller:get_line_count())
    end)

    -- GNARLY: a fresh buffer has count == 1 (phantom line), but so does a buffer
    -- with exactly one *real* line. The == 1 check can't tell them apart, so a
    -- single-line buffer's only line gets replaced rather than appended after.
    it("buffer with a single real line gets that line replaced (== 1 edge case)", function()
        -- TODO! resolve this issue
        local controller = new_buffer_controller_with_lines({ "real" })
        controller:append_styled_lines(new_lines_builder({ "one", "two" }))
        should.be_equal("one\ntwo", controller:get_lines_from(0))
    end)

    it("moves the cursor to the last line of the buffer", function()
        local controller = new_buffer_controller_with_lines({})
        controller:append_styled_lines(new_lines_builder({ "one", "two", "three" }))
        should.be_equal(2, controller:get_cursor_line_number_0indexed())
    end)
end)

describe("BufferController:replace_with_styled_lines_after", function()
    it("replaces from the middle, keeping preceding lines", function()
        local controller = new_buffer_controller_with_lines({ "one", "two", "three", "four" })
        controller:replace_with_styled_lines_after(2, new_lines_builder({ "X", "Y" }))
        should.be_equal("one\ntwo\nX\nY", controller:get_lines_from(0))
    end)

    it("replaces from the start (0), wiping everything", function()
        local controller = new_buffer_controller_with_lines({ "one", "two", "three" })
        controller:replace_with_styled_lines_after(0, new_lines_builder({ "X" }))
        should.be_equal("X", controller:get_lines_from(0))
    end)

    it("start at the end appends", function()
        local controller = new_buffer_controller_with_lines({ "one", "two" })
        controller:replace_with_styled_lines_after(2, new_lines_builder({ "three" }))
        should.be_equal("one\ntwo\nthree", controller:get_lines_from(0))
    end)

    describe("fold management", function()
        it("appending a folded block records a fold covering that block", function()
            local controller = new_buffer_controller_with_lines({})
            local builder = LinesBuilder:new(vim.api.nvim_create_namespace("buffers_test"))
            builder:append_folded_styled_lines({ "a", "b" }, "Normal")
            controller:append_styled_lines(builder)

            should.be_equal("a\nb", controller:get_lines_from(0))
            should.be_equal(1, #controller.folds)
            should.be_equal(1, controller.folds[1].start_line_base1)
            should.be_equal(2, controller.folds[1].end_line_base1)
        end)

        it("replacement keeps folds ending before the start line and drops ones at/after it", function()
            local controller = new_buffer_controller_with_lines({ "one", "two", "three", "four" })
            controller.folds = {
                Fold:new(1, 2), -- before start line 2, should be kept
                Fold:new(5, 6), -- at/after start line 2, should be dropped
            }
            controller:replace_with_styled_lines_after(2, new_lines_builder({ "X", "Y" }))

            should.be_equal("one\ntwo\nX\nY", controller:get_lines_from(0))
            should.be_equal(1, #controller.folds)
            should.be_equal(1, controller.folds[1].start_line_base1)
            should.be_equal(2, controller.folds[1].end_line_base1)
        end)
    end)
end)
