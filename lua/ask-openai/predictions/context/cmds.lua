local messages = require("devtools.messages")

local M = {}

M.commands = {} -- RESTORE?

---@return ContextItem[]
function M.get_context_items()
    local items = {}
    for _, cmd in ipairs(M.commands) do
        local output = vim.api.nvim_exec(cmd, true)
        table.insert(items, ContextItem:new(output, cmd))
    end
    return items
end

function M.dump_this()
    local items = M.get_context_items()
    messages.ensure_open()
    for _, item in ipairs(items) do
        messages.header(item.filename)
        messages.append(item.content)
    end
    messages.scroll_back_before_last_append()
end

function M.setup()
    vim.api.nvim_create_user_command("AskDumpCmdsContext", M.dump_this, {})
end

return M
