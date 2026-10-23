require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require "luassert"
local should = require("devtools.tests.should")
local describe = require('devtools.tests.describe')
local FloatWindow = require("ask-openai.helpers.float_window")
local WindowController0Indexed = require("ask-openai.rewrites.WindowController")
local BufferController0Indexed = require("ask-openai.rewrites.BufferController")

describe("FloatWindow.new", function()
    it("ensure is also a WindowController0Indexed", function()
        local float_window = FloatWindow:new({})
        expect(float_window.get_cursor_row ~= nil) -- get_cursor_row is on WindowController0Indexed
        expect(float_window.open ~= nil) -- open is on FloatWindow
        expect(float_window.buffer ~= nil) -- has buffer function
        expect(float_window:buffer())
        expect(float_window:buffer().buffer_number > 0) -- not zero
    end)
end)
