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

    it("splits prefix and suffix", function()
        local bufnr = new_buffer_with_lines(seven_lines)
        local line_base1 = 4 -- 4th line
        local col_base0 = 0 -- cursor in first col
        vim.api.nvim_win_set_cursor(0, { line_base1, col_base0 })

        local prefix, suffix = ps.get_prefix_suffix(bufnr)

        assert.equal("line 1\nline 2\nline 3\n", prefix)
        assert.equal("line 4\nline 5\nline 6\nline 7", suffix)
    end)
end)
