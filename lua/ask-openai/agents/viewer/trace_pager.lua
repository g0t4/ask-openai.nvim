local M = {}

-- * Regex patterns for trace navigation (Vim regex syntax)
local PATTERN_ALL_MESSAGES = "^\\d\\+:\\s"
local PATTERN_USER = "^\\d\\+:\\s*USER"
local PATTERN_ASSISTANT = "^\\d\\+:\\s*ASSISTANT"

--- Close NvimTree sidebar if it's open
local function close_nvim_tree_if_open()
    local ok, nvim_tree_api = pcall(require, "nvim-tree.api")
    if not ok then
        return
    end
    -- Check if the tree is actually visible before closing
    local api_tree = nvim_tree_api.tree
    if api_tree.is_visible() then
        api_tree.close()
    end
end

local function setup_trace_keymaps(bufnr)

    -- Use vim.tbl_extend to merge tables (Lua doesn't support + operator on tables)
    local base_opts = { buffer = bufnr, noremap = true, silent = true }

    -- * IDEA IS:
    --  nu => next user message
    --  then I can use `n` and `p` like normal to jump b/w occurences
    --   for some reason that is faster than vim.cmd here each time...
    --   sluggish to invoke callback each time here.. no idea why
    --  nm => next message
    --   n/p to move
    --  na => next assistant message
    --   n/p to move
    --
    -- PRN add more keymaps like
    --   nc for next command (run_process)?
    --
    vim.keymap.set("n", "nm", "", vim.tbl_extend("force", base_opts, {
        callback = function()
            vim.cmd("/" .. PATTERN_ALL_MESSAGES)
        end,
    }))

    vim.keymap.set("n", "pm", "", vim.tbl_extend("force", base_opts, {
        callback = function()
            vim.cmd("?" .. PATTERN_ALL_MESSAGES)
        end,
    }))

    vim.keymap.set("n", "nu", "", vim.tbl_extend("force", base_opts, {
        callback = function()
            vim.cmd("/" .. PATTERN_USER)
        end,
    }))

    vim.keymap.set("n", "pu", "", vim.tbl_extend("force", base_opts, {
        callback = function()
            vim.cmd("?" .. PATTERN_USER)
        end,
    }))

    vim.keymap.set("n", "na", "", vim.tbl_extend("force", base_opts, {
        callback = function()
            vim.cmd("/" .. PATTERN_ASSISTANT)
        end,
    }))

    vim.keymap.set("n", "pa", "", vim.tbl_extend("force", base_opts, {
        callback = function()
            vim.cmd("?" .. PATTERN_ASSISTANT)
        end,
    }))
end

---@param trace_path string path to a *-trace.json file
function M.open_trace_viewer(trace_path)
    -- Resolve the path (expand ~, relative paths, etc.)
    -- local resolved_path = vim.fn.expand(trace_path)
    -- local escaped_path = vim.fn.shellescape(resolved_path)

    -- TODO how about find trace path based on part of session_id or datasets dir path i.e. 2026-06-14_001?
    --  like I plan to do with session restore from datasets dir

    close_nvim_tree_if_open()

    vim.cmd("tabnew")

    vim.cmd("terminal view_trace " .. trace_path)

    local term_bufnr = vim.api.nvim_get_current_buf()
    vim.bo.scrollback = 100000
    -- FYI default is 10K and then max is 100K...
    --   IIUC -1 => maps to 10K default btw... b/c by default `=vim.bo.scrollback` shows 10K for me (hence overriding here)
    -- BTW I want to stay at top of buffer (not jump to bottom)... so that is desirable and working right now
    -- if you hit the limit you will scroll down to first line that still shows (after cutoff lines disappaer above)... so it is obvious

    setup_trace_keymaps(term_bufnr)

    -- vim.api.nvim_buf_set_name(term_bufnr, ("TraceViewer:%s"):format(resolved_path))
end

return M
