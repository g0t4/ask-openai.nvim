-- top level test imports (i.e. for completions)
local a = require("plenary.async")
local tests = require("plenary.busted")
-- plenary bundles luassert:
local assert = require 'luassert'
local match = require 'luassert.match'
-- local spy = require 'luassert.spy'
-- https://github.com/lunarmodules/luassert
-- https://github.com/nvim-lua/plenary.nvim/blob/master/TESTS_README.md

function test_env_setup_rug()
    -- IIUC PlenaryTestFile runs w/ minimal init config and thus I have to wire up some of the things I use in dotfiles repoo
    -- PRN... could I add this to my scheduler interface, so I can reuse it and ensure always registered?

    -- fix resolution of rxlua in rtp
    local plugin_path = vim.fn.stdpath("data") .. "/lazy/RxLua/"
    package.path = package.path .. ";" .. plugin_path .. "?.lua"

    -- other possibilities:
    --   -- vim.opt.runtimepath:append("~/.local/share/nvim/lazy/rxlua")
end

test_env_setup_rug()

local rx = require("rx")
local TimeoutScheduler = require("ask-openai.rx.scheduler")

tests.describe("timeout scheduler", function()
    -- FYI async.tests => https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/async/tests.lua
    a.tests.it("should unsubscribe", function()
        -- local s = TimeoutScheduler.create()
        -- s:schedule(function()
        --     assert.is_true(true)
        -- end, 1000)
        -- -- TODO how to wait for callback? uv.wait or smth? scheduler uses uv.timer_start()


        -- assert.is.equals(2, 1 + 1)
        -- assert.is_true(false)
    end)
end)

local function is_gt(state, arguments)
    local expected = arguments[1]
    return function(value)
        return value > expected
    end
end

-- assert:register("matcher", "even", is_even)
assert:register("matcher", "gt", is_gt)

tests.describe("Example async test w/ assertion using a.wrap", function()
    -- a.wrap => https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/async/async.lua#L76
    -- returns an async function (future/promise, IIUC)
    local block_until_callbacked = a.wrap(function(callback)
        vim.defer_fn(function()
            callback("wrapped_done")
        end, 200) -- simulate 200ms delay
    end, 1) -- `1` means the function has 1 callback argument

    a.tests.it("should block until async operation completes", function()
        local start_time = vim.loop.hrtime()
        local result = block_until_callbacked()
        local elapsed_ms = (vim.loop.hrtime() - start_time) / 1e6

        assert.are.equal(result, "wrapped_done")
        -- assert.is_gt(elapsed_ms, 198)
        match.is_gt(elapsed_ms, 198)
    end)
end)

--  FYI <leader>u is now mapped to test file!
--   nmap <leader>u <Plug>PlenaryTestFile
-- :PlenaryBustedFile .config/nvim/lua/tests.lua
