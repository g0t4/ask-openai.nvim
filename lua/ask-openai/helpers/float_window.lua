local M = {}

-- PRN use this as base for ChatWindow?

local function centered_window(opts)
    opts.width = opts.width or 0.6
    opts.height = opts.height or 0.6

    -- PRN minimum width? basically a point at which the window is allowed to cover more than 50% wide and 80% tall
    local win_height = math.ceil(opts.height * vim.o.lines)
    local win_width = math.ceil(opts.width * vim.o.columns)
    local top_is_at_row = math.floor((vim.o.lines - win_height) / 2)
    local left_is_at_col = math.floor((vim.o.columns - win_width) / 2)
    return {
        relative = "editor",
        width = win_width,
        height = win_height,

        row = top_is_at_row,
        col = left_is_at_col,
        style = "minimal",
        border = "single", -- "rounded"
    }
end

function M.open_float(lines, opts)
    opts = opts or {}

    -- * create a scratch buffer
    local listed_buffer = false
    local scratch_buffer = true -- must be scratch, otherwise have to save contents or trash it on exit
    local buffer_number = vim.api.nvim_create_buf(listed_buffer, scratch_buffer)

    -- * lines to buffer
    vim.api.nvim_buf_set_lines(buffer_number, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buffer_number, "filetype", opts.filetype or "")

    -- * open the floating window
    local win = vim.api.nvim_open_win(buffer_number, true, centered_window(opts))

    vim.api.nvim_create_autocmd("VimResized", {
        group = gid,
        callback = function()
            if not vim.api.nvim_win_is_valid(win) then return end
            vim.api.nvim_win_set_config(win, centered_window(opts))
        end,
    })

    -- when THIS window closes, drop its autocmds
    vim.api.nvim_create_autocmd("WinClosed", {
        group = gid,
        pattern = tostring(win),
        callback = function()
            pcall(vim.api.nvim_del_augroup_by_id, gid)
        end,
        once = true,
    })

    return buffer_number, win
end

return M
