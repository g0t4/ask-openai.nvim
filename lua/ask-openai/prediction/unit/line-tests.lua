local a = require("plenary.async")
local tests = require("plenary.busted")
local assert = require 'luassert'
local match = require 'luassert.match'

require("ask-openai.rx.tests-setup")

local handlers = require("ask-openai.prediction.handlers")

describe("get_line_range", function()
    it("allowed lines both before/after are within document", function()
        local current_row = 40
        local allow_lines = 10
        local total_rows = 100

        local first_row, last_row = handlers.get_line_range(current_row, allow_lines, total_rows)

        assert.equals(30, first_row)
        assert.equals(50, last_row)
    end)

    it("current line is less than allowed lines, adds before's overflow to last_row", function()
        local current_row = 4
        local allow_lines = 10
        local total_rows = 100
        local first_row, last_row = handlers.get_line_range(current_row, allow_lines, total_rows)
        assert.equals(0, first_row)
        -- 6 extra overflow lines from before, 10+6==16
        --    16+4 = 20
        assert.equals(20, last_row)
    end)

    it("current line is greater than total_lines - allow_lines, adds after's overflow to first_row", function()
        local current_row = 95
        local allow_lines = 10
        local total_rows = 100

        local first_row, last_row = handlers.get_line_range(current_row, allow_lines, total_rows)
        -- local first_row, last_row = handlers.get_line_range(current_row, allow_lines, total_rows)
        -- 5 extra overflow lines from after, 10+5==15
        -- 95-15==80
        assert.equals(80, first_row)
        assert.equals(100, last_row)
    end)

    it("total rows is less than allowed lines in both directions, takes all lines", function()
        local current_row = 4
        local allow_lines = 10
        local total_rows = 8
        local first_row, last_row = handlers.get_line_range(current_row, allow_lines, total_rows)
        assert.equals(0, first_row)
        assert.equals(8, last_row)
    end)

    it("current_row + allow_lines == total_rows", function()
        -- arguably redundant, boundary condition
        local current_row = 90
        local allow_lines = 10
        local total_rows = 100
        local first_row, last_row = handlers.get_line_range(current_row, allow_lines, total_rows)
        assert.equals(80, first_row)
        assert.equals(100, last_row)
    end)
end)
