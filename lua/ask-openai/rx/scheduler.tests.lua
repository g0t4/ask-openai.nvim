require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require 'luassert'
local match = require 'luassert.match'
-- top level test imports (i.e. for completions)
local a = require("plenary.async")
local tests = require("plenary.busted")
-- plenary bundles luassert:
-- local spy = require 'luassert.spy'
-- https://github.com/lunarmodules/luassert
-- https://github.com/nvim-lua/plenary.nvim/blob/master/TESTS_README.md

local rx = require("rx")
local TimeoutScheduler = require("ask-openai.rx.scheduler")

tests.describe("timeout scheduler", function()
    -- FYI async.tests => https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/async/tests.lua
    a.tests.it("should unsubscribe", function()
        local s = TimeoutScheduler.create()
        local block_until = a.wrap(function(callback)
            s:schedule(function()
                callback("elapsed")
            end, 100)
        end, 1)

        local start_time = vim.uv.hrtime()
        local result = block_until()
        local elapsed_ms = (vim.uv.hrtime() - start_time) / 1e6

        assert.are.equal(result, "elapsed")
        assert(elapsed_ms > 90, "should block for approximately 100ms")
    end)
end)

-- tests.describe("Example async test w/ assertion using a.wrap", function()
--     -- a.wrap => https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/async/async.lua#L76
--     -- returns an async function (future/promise, IIUC)
--     local block_until_callbacked = a.wrap(function(callback)
--         vim.defer_fn(function()
--             callback("wrapped_done")
--         end, 200) -- simulate 200ms delay
--     end, 1) -- `1` means the function has 1 callback argument
--
--     a.tests.it("should block until async operation completes", function()
--         local start_time = vim.uv.hrtime()
--         local result = block_until_callbacked()
--         local elapsed_ms = (vim.uv.hrtime() - start_time) / 1e6
--
--         assert.are.equal(result, "wrapped_done")
--         assert(elapsed_ms > 190, "should block for approximately 200ms")
--     end)
-- end)

--  FYI <leader>u is now mapped to test file!
--   nmap <leader>u <Plug>PlenaryTestFile
-- :PlenaryBustedFile .config/nvim/lua/tests.lua
