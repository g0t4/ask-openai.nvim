local M = {}

function M.test_setup_add_devtools_to_package_path()
    local plugin_path = os.getenv("HOME") .. "/repos/github/g0t4/devtools.nvim/lua/"
    package.path = package.path .. ";" .. plugin_path .. "?.lua"
end

return M
