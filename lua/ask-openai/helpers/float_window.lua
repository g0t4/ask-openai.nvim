---@class FloatWindow
---@field buffer_number? integer
---@field win_id? integer
local FloatWindow = {}

---@param opts FloatWindowOptions
function FloatWindow.centered_window(opts)
    opts.width_ratio = opts.width_ratio or 0.6
    opts.height_ratio = opts.height_ratio or 0.6

    -- PRN minimum width? basically a point at which the window is allowed to cover more than 50% wide and 80% tall
    local win_height = math.ceil(opts.height_ratio * vim.o.lines)
    local win_width = math.ceil(opts.width_ratio * vim.o.columns)
    local top_is_at_row = math.floor((vim.o.lines - win_height) / 2)
    local left_is_at_col = math.floor((vim.o.columns - win_width) / 2)
    return {
        -- position:
        row = top_is_at_row,
        col = left_is_at_col,
        -- size:
        width = win_width,
        height = win_height,
        -- attributes:
        relative = "editor",
        style = "minimal",
        border = "single", -- "rounded"
    }
end

---@class FloatWindowOptions
---@field width_ratio? number -- ratio 0 to 1
---@field height_ratio? number -- ratio 0 to 1
---@field filetype? string

---@param opts FloatWindowOptions
---@param initial_lines? string[]
---@return FloatWindow
function FloatWindow:new(opts, initial_lines)
    local instance_mt = { __index = self }
    local instance = setmetatable({}, instance_mt)
    self.opts = opts or {}
    local opts = self.opts

    -- * create a scratch buffer
    local NOT_LISTED_BUFFER = false
    local IS_SCRATCH_BUFFER = true -- must be scratch, otherwise have to save contents or trash it on exit
    instance.buffer_number = vim.api.nvim_create_buf(NOT_LISTED_BUFFER, IS_SCRATCH_BUFFER)

    -- * lines to buffer
    if initial_lines then
        vim.api.nvim_buf_set_lines(instance.buffer_number, 0, -1, false, initial_lines)
    end
    vim.api.nvim_set_option_value('filetype', opts.filetype, { buf = instance.buffer_number })

    -- * open the floating window
    instance.win_id = vim.api.nvim_open_win(instance.buffer_number, true, instance.centered_window(opts))

    -- * make window resizable
    local gid = vim.api.nvim_create_augroup("float_window_" .. instance.win_id, { clear = true })
    vim.api.nvim_create_autocmd("VimResized", {
        group = gid,
        callback = function()
            if not vim.api.nvim_win_is_valid(instance.win_id) then return end
            vim.api.nvim_win_set_config(instance.win_id, instance.centered_window(opts))
        end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = gid,
        pattern = tostring(instance.win_id),
        callback = function()
            -- when THIS window closes, drop its autocmds
            pcall(vim.api.nvim_del_augroup_by_id, gid)
        end,
        once = true,
    })

    return instance
end

return FloatWindow
