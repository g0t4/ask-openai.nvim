local assert = require 'luassert'

local function is_gt(state, arguments)
    local expected = arguments[1]
    return function(value)
        return value > expected
    end
end
assert:register("matcher", "gt", is_gt)

function test_env_setup_rug()
    -- IIUC PlenaryTestFile runs w/ minimal init config and thus I have to wire up some of the things I use in dotfiles repoo
    -- PRN... could I add this to my scheduler interface, so I can reuse it and ensure always registered?

    -- fix resolution of rxlua in rtp
    local plugin_path = vim.fn.stdpath("data") .. "/lazy/RxLua/"
    package.path = package.path .. ";" .. plugin_path .. "?.lua"

    -- other possibilities:
    --   -- vim.opt.runtimepath:append("~/.local/share/nvim/lazy/rxlua")
end
