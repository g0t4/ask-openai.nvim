local log = require("ask-openai.logs.logger"):predictions()
---@class FloatWindow
---@field buffer_number? integer
---@field win_id? integer
---@field opts FloatWindowOptions
local FloatWindow = {}

---@param opts FloatWindowOptions
---@return vim.api.keyset.win_config
function FloatWindow.window_config(opts)
    opts.width_ratio = opts.width_ratio or 0.6
    opts.height_ratio = opts.height_ratio or 0.6

    -- PRN minimum width? basically a point at which the window is allowed to cover more than 50% wide and 80% tall
    local win_height = math.ceil(opts.height_ratio * vim.o.lines)
    local win_width = math.ceil(opts.width_ratio * vim.o.columns)
    local top_is_at_row = math.floor((vim.o.lines - win_height) / 2)
    local left_is_at_col = math.floor((vim.o.columns - win_width) / 2)

    ---@type vim.api.keyset.win_config
    local config = {
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
    return config
end

---@class FloatWindowOptions
---@field width_ratio? number -- ratio 0 to 1
---@field height_ratio? number -- ratio 0 to 1
---@field filetype? string
---@field buffer_name? string

---@param opts FloatWindowOptions
---@param initial_lines? string[]
---@return FloatWindow
function FloatWindow:new(opts, initial_lines)
    local instance_mt = { __index = self }
    local instance = setmetatable({ opts = opts, }, instance_mt)

    -- * create a scratch buffer
    local NOT_LISTED_BUFFER = false
    local IS_SCRATCH_BUFFER = true -- must be scratch, otherwise have to save contents or trash it on exit
    instance.buffer_number = vim.api.nvim_create_buf(NOT_LISTED_BUFFER, IS_SCRATCH_BUFFER)

    -- * lines to buffer
    if initial_lines then
        vim.api.nvim_buf_set_lines(instance.buffer_number, 0, -1, false, initial_lines)
    end

    if opts.filetype then
        vim.api.nvim_set_option_value('filetype', opts.filetype, { buf = instance.buffer_number })
    end

    if opts.buffer_name then
        vim.api.nvim_buf_set_name(instance.buffer_number, opts.buffer_name)
    end

    instance:open()

    return instance
end

function FloatWindow:open()
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        return
    end
    local initial_config = self.window_config(self.opts)
    self.win_id = vim.api.nvim_open_win(self.buffer_number, true, initial_config)

    -- * make window resizable
    local group_id = vim.api.nvim_create_augroup("float_window_" .. self.win_id, { clear = true })
    vim.api.nvim_create_autocmd("VimResized", {
        group = group_id,
        callback = function()
            if not vim.api.nvim_win_is_valid(self.win_id) then return end
            local resized_config = self.window_config(self.opts)
            vim.api.nvim_win_set_config(self.win_id, resized_config)
        end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group_id,
        pattern = tostring(self.win_id),
        callback = function()
            -- when THIS window closes, drop its autocmds
            pcall(vim.api.nvim_del_augroup_by_id, group_id)
        end,
        once = true,
    })
end

---@param title string
function FloatWindow:set_title(title)
    if not title then
        log:info("set_title is missing the title", title)
    end
    title = title or ""
    vim.schedule(function()
        if not self.win_id or not vim.api.nvim_win_is_valid(self.win_id) then
            return
        end
        vim.api.nvim_win_set_config(self.win_id, { title = " " .. title .. " ", title_pos = "center" })
    end)
end

return FloatWindow
