local M = {}

local default_opts = {
    model = "gpt-4o",
    on_the_fly_hints = true, -- startup with them on or off (also gonna add runtime toggle)
    -- todo config normal mode and/or cmdline mode hints
}

function M.set_user_opts(opts)
    M.user_opts = vim.tbl_deep_extend("force", default_opts, opts or {})
end

return M
