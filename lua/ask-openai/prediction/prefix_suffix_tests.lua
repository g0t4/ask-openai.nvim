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

        local take_lines = 2
        local prefix, suffix = ps.get_prefix_suffix(take_lines)

        -- assert.equal("", prefix) -- TODO FIX FOR new line not expected!
        assert.equal("line 1\nline 2\nline 3\nline 4\nline 5", suffix)
    end)
end)


local ps = require("ask-openai.prediction.prefix_suffix")

describe("determine_line_range", function()
    it("plenty of lines for both prefix and suffix", function()
        local current_row_base0 = 40
        local take_num_lines_each_way = 10
        local buffer_line_count = 100

        local start_row_base0, end_row_base0 = ps.determine_line_range_base0(current_row_base0, take_num_lines_each_way, buffer_line_count)

        assert.equal(30, start_row_base0)
        assert.equal(50, end_row_base0)
    end)

    it("unused prefix lines are added to the suffix", function()
        local current_row_base0 = 4
        local take_num_lines_each_way = 10
        local buffer_line_count = 100
        local start_row_base0, end_row_base0 = ps.determine_line_range_base0(current_row_base0, take_num_lines_each_way, buffer_line_count)
        assert.equal(0, start_row_base0)
        -- 6 extra overflow lines from before, 10+6==16
        --    16+4 = 20
        --    (note 21 rows total with current_row)
        assert.equal(20, end_row_base0)
    end)

    it("unused suffix lines are added to the prefix", function()
        local current_row_base0 = 95
        local take_num_lines_each_way = 10
        local buffer_line_count = 100

        local start_row_base0, end_row_base0 = ps.determine_line_range_base0(current_row_base0, take_num_lines_each_way, buffer_line_count)
        -- 5 extra overflow lines from after, 10+5==15
        -- 95-15==80
        assert.equal(80, start_row_base0)
        assert.equal(99, end_row_base0)
    end)

    it("current_row is before the start of the document, takes start of document", function()
        local current_row_base0 = -5
        local take_num_lines_each_way = 10
        local buffer_line_count = 100

        local start_row_base0, end_row_base0 = ps.determine_line_range_base0(current_row_base0, take_num_lines_each_way, buffer_line_count)
        -- 5 extra overflow lines from after, 10+5==15
        -- 95-15==80
        assert.equal(0, start_row_base0)
        assert.equal(20, end_row_base0)
    end)

    it("current_row is past the end of the document, still takes end of document", function()
        local current_row_base0 = 115
        local take_num_lines_each_way = 10
        local buffer_line_count = 100

        local start_row_base0, end_row_base0 = ps.determine_line_range_base0(current_row_base0, take_num_lines_each_way, buffer_line_count)
        -- 5 extra overflow lines from after, 10+5==15
        -- 95-15==80
        -- PRN should this be 79 too since the cursor line could be added to prefix too :)... NBD for now
        assert.equal(80, start_row_base0)
        assert.equal(99, end_row_base0)
    end)

    it("buffer line count is less than allowed lines in both directions, takes all lines", function()
        local current_row_base0 = 4
        local take_num_lines_each_way = 10
        local buffer_line_count = 8
        local start_row_base0, end_row_base0 = ps.determine_line_range_base0(current_row_base0, take_num_lines_each_way, buffer_line_count)
        assert.equal(0, start_row_base0)
        assert.equal(7, end_row_base0)
    end)

    it("suffix has remainder of document through exactly the last line", function()
        -- arguably redundant, boundary condition
        local current_row_base0 = 89
        local take_num_lines_each_way = 10
        local buffer_line_count = 100
        local start_row, end_row_base0 = ps.determine_line_range_base0(current_row_base0, take_num_lines_each_way, buffer_line_count)
        assert.equal(79, start_row)
        assert.equal(99, end_row_base0)
    end)
end)
