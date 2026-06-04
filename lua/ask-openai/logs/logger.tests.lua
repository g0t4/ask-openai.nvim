require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require 'luassert'
local buffers = require('devtools.tests.buffers')
local describe = require('devtools.tests.define.describe')

describe("test log_auto_inspect", function()
    local log = require("ask-openai.logs.logger"):predictions() -- for now use my single logger is fine
    local captures = {}
    local original_log
    log.log = function(self, level, ...)
        table.insert(captures, { level = level, args = { ... } })
    end

    before_each(function()
        captures = {}
    end)

    it("table is vim.inspect'd", function()
        local tbl = { a = 1, b = 2 }
        log:info("message", 1, tbl)
        assert.equals(1, #captures)
        assert.equals([[{
  a = 1,
  b = 2
}]], captures[1].args[3])
    end)

    it("pass nil before last arg => doesn't drop 'last'", function()
        -- classic enumeration bug in lua with ipairs!
        log:info("message", "first", nil, "last")
        assert.equals(3, #captures)
        assert.equals("last", captures[3].args[3])
    end)
end)
