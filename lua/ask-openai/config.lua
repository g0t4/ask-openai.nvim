local M = {}

local default_opts = {
    model = "gpt-4o",
    log_path = "~/.ask.openai.log"
}

function M.set_user_opts(opts)
    M.user_opts = vim.tbl_deep_extend("force", default_opts, opts or {})
end

return M
