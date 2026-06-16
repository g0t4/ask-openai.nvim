local log = require("ask-openai.logs.logger"):universal()
---@class FloatWindow
---@field buffer_number? integer
---@field win_id? integer
---@field opts FloatWindowOptions
local FloatWindow = {}

--- Find a buffer by name, or nil if not found.
---
---@param buf_name string
---@return integer|nil bufnr
local function find_buffer_by_name(buf_name)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name == buf_name then
            return bufnr
        end
    end
    return nil
end

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

--- Create a new FloatWindow instance, reusing an existing buffer if one with the same name exists.
--- This prevents E95 errors when reopening windows.
---
---@param opts FloatWindowOptions
---@param initial_lines? string[]
---@return FloatWindow
function FloatWindow:new(opts, initial_lines)
    local instance_mt = { __index = self }
    local instance = setmetatable({ opts = opts, }, instance_mt)

    -- * reuse existing buffer if one with the same name exists (prevents E95 on reopen)
    if opts.buffer_name then
        local existing_bufnr = find_buffer_by_name(opts.buffer_name)
        if existing_bufnr and vim.api.nvim_buf_is_valid(existing_bufnr) then
            instance.buffer_number = existing_bufnr
        else
            -- * create a new scratch buffer
            local NOT_LISTED_BUFFER = false
            local IS_SCRATCH_BUFFER = true
            instance.buffer_number = vim.api.nvim_create_buf(NOT_LISTED_BUFFER, IS_SCRATCH_BUFFER)

            if opts.filetype then
                vim.api.nvim_set_option_value('filetype', opts.filetype, { buf = instance.buffer_number })
            end

            vim.api.nvim_buf_set_name(instance.buffer_number, opts.buffer_name)
        end
    else
        -- * create a new scratch buffer (no name)
        local NOT_LISTED_BUFFER = false
        local IS_SCRATCH_BUFFER = true
        instance.buffer_number = vim.api.nvim_create_buf(NOT_LISTED_BUFFER, IS_SCRATCH_BUFFER)

        if opts.filetype then
            vim.api.nvim_set_option_value('filetype', opts.filetype, { buf = instance.buffer_number })
        end
    end

    -- * lines to buffer
    if initial_lines then
        vim.api.nvim_buf_set_lines(instance.buffer_number, 0, -1, false, initial_lines)
    end

    instance:open()

    return instance
end

--- Open (or reopen) the float window.
--- If the window is already open, does nothing.
--- If the window was closed but buffer exists, reopens it.
function FloatWindow:open()
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        return
    end

    if not self.buffer_number or not vim.api.nvim_buf_is_valid(self.buffer_number) then
        log:error("FloatWindow:open called with invalid buffer")
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

--- Close the float window and delete its buffer.
--- This fully cleans up the instance so it can be recreated fresh on next open().
function FloatWindow:close()
    -- * close window if valid
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        vim.api.nvim_win_close(self.win_id, true)
        self.win_id = nil
    end

    -- * delete buffer if valid (prevents E95 on next open)
    if self.buffer_number and vim.api.nvim_buf_is_valid(self.buffer_number) then
        pcall(vim.api.nvim_buf_delete, self.buffer_number, { force = true })
        self.buffer_number = nil
    end
end

---@param title string
function FloatWindow:set_title(title, footer)
    vim.schedule(function()
        if not self.win_id or not vim.api.nvim_win_is_valid(self.win_id) then
            return
        end
        local config = {}
        if title then
            config.title = " " .. title .. " "
            config.title_pos = "center"
        end
        if footer then
            config.footer = " " .. footer .. " "
            config.footer_pos = "center"
        end
        vim.api.nvim_win_set_config(self.win_id, config)
    end)
end

return FloatWindow
