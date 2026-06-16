require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require 'luassert'
local buffers = require('devtools.tests.buffers')
local describe = require('devtools.tests.define.describe')

describe("test log_auto_inspect", function()
    local log = require("ask-openai.logs.logger"):universal() -- for now use my single logger is fine
    local captures = {}
    log._log = function(self, entry)
        table.insert(captures, entry)
    end

    before_each(function()
        captures = {}
    end)

    it("table is vim.inspect'd", function()
        local tbl = { a = 1, b = 2 }
        log:info("message", tbl)
        assert.equals(1, #captures)
        assert.matches([[message {
  a = 1,
  b = 2
}]], captures[1])
    end)

    it("pass nil before last arg => doesn't drop 'last'", function()
        -- classic enumeration bug in lua with ipairs!
        log:info("message", "first", nil, "last")
        assert.equals(1, #captures)
        assert.matches("message first nil last\n", captures[1])
    end)

    -- TODO do I really want " " to join when multiple ... args logged in one call?
    --   ? how often do I even pass more than one? how about just log each on its own line?
    -- TODO add other tests of logging as needed for quirks that are otherwise hard to debug
end)
