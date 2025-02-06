local a = require("plenary.async")
local tests = require("plenary.busted")
local assert = require 'luassert'
local match = require 'luassert.match'

require("ask-openai.rx.tests-setup")
test_env_setup_rug()

local handlers = require("ask-openai.prediction.handlers")

describe("get_line_range", function()
    it("allowed lines within document", function()
        local current_row = 40
        local allow_lines = 10
        local total_rows = 100

        local first_row, last_row = handlers.get_line_range(current_row, allow_lines, total_rows)

        assert.equals(30, first_row)
        assert.equals(50, last_row)
    end)

    -- it("some other test", function()
    --     -- assert.equals(0, bounter)
    -- end)
    --
end)
