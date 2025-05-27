local M = {}

local function add_devtools_to_package_path()
    local plugin_path = os.getenv("HOME") .. "/repos/github/g0t4/devtools.nvim/lua/"
    package.path = package.path .. ";" .. plugin_path .. "?.lua"
end

function M.add_test_deps_to_package_path()
    add_devtools_to_package_path()
end

return M
