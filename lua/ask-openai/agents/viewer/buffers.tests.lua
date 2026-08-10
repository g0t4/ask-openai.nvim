-- testing modules:
require("ask-openai.helpers.test_setup").modify_package_path()
local should = require('devtools.tests.should')
local describe = require('devtools.tests.define.describe')
local test_buffers = require('devtools.tests.buffers')
-- system under test:
local BufferController = require('ask-openai.agents.viewer.buffers')

--- Create a fresh BufferController backed by a new test buffer with the given lines.
---@param lines string[]
---@return BufferController
local function make_controller(lines)
    local bufnr = test_buffers.new_buffer_with_lines(lines)
    return BufferController:new(bufnr)
end

describe("BufferController:get_lines_after", function()
    describe("start at first line (0)", function()
        it("returns every line joined by \\n", function()
            local controller = make_controller({ "one", "two", "three" })
            should.be_equal("one\ntwo\nthree", controller:get_lines_after(0))
        end)

        it("single line buffer", function()
            local controller = make_controller({ "only" })
            should.be_equal("only", controller:get_lines_after(0))
        end)
    end)

    describe("start in the middle", function()
        it("returns all lines from that point onward", function()
            local controller = make_controller({ "one", "two", "three", "four" })
            should.be_equal("three\nfour", controller:get_lines_after(2))
        end)
    end)

    describe("start at last line", function()
        it("returns only the last line", function()
            local controller = make_controller({ "one", "two", "three" })
            should.be_equal("three", controller:get_lines_after(2))
        end)
    end)

    describe("start at or beyond end of buffer", function()
        it("returns empty string when index equals line count", function()
            local controller = make_controller({ "one", "two" })
            should.be_equal("", controller:get_lines_after(2))
        end)

        it("returns empty string when index is far beyond line count", function()
            local controller = make_controller({ "one", "two" })
            should.be_equal("", controller:get_lines_after(10))
        end)
    end)

    describe("empty buffer", function()
        it("returns empty string", function()
            local controller = make_controller({})
            should.be_equal("", controller:get_lines_after(0))
        end)
    end)

    describe("blank lines preserved", function()
        it("keeps blank lines in the result", function()
            local controller = make_controller({ "one", "", "two", "", "three" })
            should.be_equal("\ntwo\n\nthree", controller:get_lines_after(1))
        end)
    end)
end)
