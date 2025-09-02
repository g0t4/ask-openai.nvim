local M = {}

local function add_plugin_to_package_path(plugin_path)
    package.path = package.path .. ";" .. plugin_path .. "?.lua"
    package.path = package.path .. ";" .. plugin_path .. "?/init.lua"
end

local function add_rxlua_to_package_path()
    -- IIUC PlenaryTestFile runs w/ minimal init config and thus I have to wire up some of the things I use in dotfiles repoo
    -- PRN... could I add this to my scheduler interface, so I can reuse it and ensure always registered?

    -- fix resolution of rxlua in rtp
    local plugin_path = vim.fn.stdpath("data") .. "/lazy/RxLua/"
    add_plugin_to_package_path(plugin_path)
    -- other possibilities:
    --   -- vim.opt.runtimepath:append("~/.local/share/nvim/lazy/rxlua")
end

local function add_devtools_to_package_path()
    local plugin_path = os.getenv("HOME") .. "/repos/github/g0t4/devtools.nvim/lua/"
    add_plugin_to_package_path(plugin_path)
end


function M.modify_package_path()
    add_devtools_to_package_path()
    add_rxlua_to_package_path()
end

return M
