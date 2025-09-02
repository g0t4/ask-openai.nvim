local a = require("plenary.async")
local tests = require("plenary.busted")
local assert = require 'luassert'
local match = require 'luassert.match'

require("ask-openai.rx.tests-setup")

local handlers = require("ask-openai.prediction.handlers")

describe("get_prefix_suffix", function()
    local lines_1_to_30 = {}
    for i = 1, 30 do
        lines_1_to_30[i] = "line " .. i
    end

    it("", function()
        load_lines(lines_1_to_30)
    end)
end)
