require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require "luassert"
local should = require("devtools.tests.should")
local describe = require('devtools.tests.define.describe')

local UserInputWindow = require("ask-openai.agents.viewer.user_input_window")

describe("UserInputWindow", function()
    it("creates a new UserInputWindow instance", function()
        local UserInputWindow = require("ask-openai.agents.viewer.user_input_window")
        local win = UserInputWindow:new()
        assert.is_table(win)
        assert.are_equal(win.opts.buffer_name, "AskAgentInput")

        -- ? hrmmm... better way to test metatable setup properly?
        --  this works too!
        assert.are_equal(UserInputWindow.hide, win.hide)
        assert.are_equal(UserInputWindow.window_config, win.window_config)
    end)
end)
