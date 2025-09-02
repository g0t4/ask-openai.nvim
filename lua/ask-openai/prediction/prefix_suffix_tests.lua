local assert = require 'luassert'
require("ask-openai.helpers.test_setup").modify_package_path()
require("ask-openai.helpers.buffer_testing")

local ps = require("ask-openai.prediction.prefix_suffix")

describe("get_prefix_suffix", function()
    local function create_lines(num_lines)
        local lines = {}
        for i = 1, num_lines do
            lines[i] = "line " .. i
        end
        return lines
    end

    local seven_lines = {
        "line 1", "line 2", "line 3", "line 4", "line 5",
        "line 6", "line 7"
    }

    it("in middle of buffer, returns prefix and suffix", function()
        local bufnr = new_buffer_with_lines(seven_lines)
        local line_base1 = 4 -- 4th line
        local col_base0 = 0 -- cursor in first col
        vim.api.nvim_win_set_cursor(0, { line_base1, col_base0 })

        local prefix, suffix = ps.get_prefix_suffix()

        assert.equal("line 1\nline 2\nline 3\n", prefix)
        assert.equal("line 4\nline 5\nline 6\nline 7", suffix)
    end)

    it("cursor is at start of buffer, first line, first col", function()
        local bufnr = new_buffer_with_lines(seven_lines)
        local line_base1 = 1
        local col_base0 = 0
        vim.api.nvim_win_set_cursor(0, { line_base1, col_base0 })

        local prefix, suffix = ps.get_prefix_suffix()

        assert.equal("", prefix)
    end)
end)


local ps = require("ask-openai.prediction.prefix_suffix")

describe("get_line_range", function()
    it("allowed lines both before/after are within document", function()
        local current_row = 40
        local take_num_lines_each_way = 10
        local total_rows = 100

        local first_row, last_row = ps.get_line_range_base0(current_row, take_num_lines_each_way, total_rows)

        assert.equal(30, first_row)
        assert.equal(50, last_row)
    end)

    it("current line is less than allowed lines, adds before's overflow to last_row", function()
        local current_row = 4
        local take_num_lines_each_way = 10
        local total_rows = 100
        local first_row, last_row = ps.get_line_range_base0(current_row, take_num_lines_each_way, total_rows)
        assert.equal(0, first_row)
        -- 6 extra overflow lines from before, 10+6==16
        --    16+4 = 20
        assert.equal(20, last_row)
    end)

    it("current line is greater than total_lines - take_num_lines_each_way, adds after's overflow to first_row", function()
        local current_row = 95
        local take_num_lines_each_way = 10
        local total_rows = 100

        local first_row, last_row = ps.get_line_range_base0(current_row, take_num_lines_each_way, total_rows)
        -- local first_row, last_row = handlers.get_line_range(current_row, take_num_lines_each_way, total_rows)
        -- 5 extra overflow lines from after, 10+5==15
        -- 95-15==80
        assert.equal(80, first_row)
        assert.equal(100, last_row)
    end)

    it("total rows is less than allowed lines in both directions, takes all lines", function()
        local current_row = 4
        local take_num_lines_each_way = 10
        local total_rows = 8
        local first_row, last_row = ps.get_line_range_base0(current_row, take_num_lines_each_way, total_rows)
        assert.equal(0, first_row)
        assert.equal(8, last_row)
    end)

    it("enough lines to take take_num_lines_each_way", function()
        -- arguably redundant, boundary condition
        local current_row = 90
        local take_num_lines_each_way = 10
        local total_rows = 100
        local first_row, last_row = ps.get_line_range_base0(current_row, take_num_lines_each_way, total_rows)
        assert.equal(80, first_row)
        assert.equal(100, last_row)
    end)
end)
