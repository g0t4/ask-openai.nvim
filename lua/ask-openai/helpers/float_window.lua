local log = require("devtools.logs.logger"):universal()
local WindowController0Indexed = require("ask-openai.rewrites.WindowController")

---@class FloatWindow : WindowController0Indexed
---@field buffer_number? integer
---@field opts FloatWindowOptions
local FloatWindow = {}
setmetatable(FloatWindow, { __index = WindowController0Indexed })
FloatWindow.__index = FloatWindow
-- float window now subclasses WindowController0Indexed
--  IOTW it is a controllable window!

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
function FloatWindow:new(opts, initial_lines)
    -- FYI! I decided to keep setmetadata/__index out of the new() heirarchy for window types... NBD if you want to add it back but don't fuck up subclassing
    -- when possible limit new to field initialization, save all inheritance out of here b/c it can become confusing if conflated
    --  and push setting metatable to the leaf most type (wherever the instance's table is first created)
    local instance = self -- self allows for subclassing where the caller would handle inheritance, not me here
    instance.opts = opts

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

    FloatWindow.open(instance)
    -- critical to call super type's new as well, and after open so we have the window id
    WindowController0Indexed.new(instance, instance.window_id) -- init window controller fields!
    return instance
end

--- Open (or reopen) the window.
--- TODO rename ensure_open?
--- If the window is already open, does nothing.
--- If the window was closed but buffer exists, reopens it.
function FloatWindow:open()
    local window_is_already_open = self.window_id and vim.api.nvim_win_is_valid(self.window_id)
    if window_is_already_open then
        return
    end
    -- window is not open (never open, or closed) => so, open it

    if not self.buffer_number or not vim.api.nvim_buf_is_valid(self.buffer_number) then
        log:error("FloatWindow:open called with invalid buffer")
        return
    end

    local initial_config = self.window_config(self.opts)

    -- `winhighlight` is a window option, not an nvim_open_win config key, so pull it
    -- out and apply it after the window exists (e.g. for borderless bg-colored panes).
    local winhighlight = initial_config.winhighlight
    initial_config.winhighlight = nil

    self.window_id = vim.api.nvim_open_win(self.buffer_number, true, initial_config)

    if winhighlight then
        vim.api.nvim_set_option_value('winhighlight', winhighlight, { win = self.window_id })
    end

    -- * make window resizable
    local group_id = vim.api.nvim_create_augroup("float_window_" .. self.window_id, { clear = true })
    vim.api.nvim_create_autocmd("VimResized", {
        group = group_id,
        callback = function()
            if not vim.api.nvim_win_is_valid(self.window_id) then return end
            local resized_config = self.window_config(self.opts)
            -- `winhighlight` is not a valid nvim_win_set_config key (it's a win option)
            resized_config.winhighlight = nil
            vim.api.nvim_win_set_config(self.window_id, resized_config)
        end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group_id,
        pattern = tostring(self.window_id),
        callback = function()
            -- when THIS window closes, drop its autocmds
            pcall(vim.api.nvim_del_augroup_by_id, group_id)
        end,
        once = true,
    })
end

--- Resize the window from window_config (e.g. when the user input box grows to
--- fit a long prompt, or the chat shrinks to make room).
function FloatWindow:resize()
    if not self.window_id or not vim.api.nvim_win_is_valid(self.window_id) then return end
    local config = self.window_config(self.opts)
    -- `winhighlight` is a window option, not an nvim_win_set_config key.
    local winhighlight = config.winhighlight
    config.winhighlight = nil
    vim.api.nvim_win_set_config(self.window_id, config)
    if winhighlight then
        vim.api.nvim_set_option_value('winhighlight', winhighlight, { win = self.window_id })
    end
end

--- Close the float window and delete its buffer.
--- This fully cleans up the instance so it can be recreated fresh on next open().
function FloatWindow:close()
    -- * close window if valid
    if self.window_id and vim.api.nvim_win_is_valid(self.window_id) then
        vim.api.nvim_win_close(self.window_id, true)
        self.window_id = nil
    end

    -- * delete buffer if valid (prevents E95 on next open)
    if self.buffer_number and vim.api.nvim_buf_is_valid(self.buffer_number) then
        pcall(vim.api.nvim_buf_delete, self.buffer_number, { force = true })
        self.buffer_number = nil
    end
end

---@param title string
function FloatWindow:set_title(title)
    vim.schedule(function()
        local win_is_valid = self.window_id and vim.api.nvim_win_is_valid(self.window_id)
        if not title or not win_is_valid then
            log:warn("Cannot set title", { win_id = self.window_id, title = title, })
            return
        end
        local config = {}
        config.title = " " .. title .. " "
        config.title_pos = "center"
        vim.api.nvim_win_set_config(self.window_id, config)
    end)
end

--- Only set footer (w/o changing title)
---@param footer string
function FloatWindow:set_footer(footer)
    vim.schedule(function()
        local win_is_valid = self.window_id and vim.api.nvim_win_is_valid(self.window_id)
        if not footer or not win_is_valid then
            log:warn("Cannot set footer", { win_id = self.window_id, footer = footer, })
            return
        end
        local config = {}
        config.footer = " " .. footer .. " "
        config.footer_pos = "center"
        vim.api.nvim_win_set_config(self.window_id, config)
    end)
end

return FloatWindow
