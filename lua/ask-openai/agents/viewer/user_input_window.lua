local FloatWindow = require("ask-openai.helpers.float_window")

--- Fixed height (in rows) of the user message input box.
local INPUT_HEIGHT = 3

---@class UserInputWindow : FloatWindow
---@field buffer_number number
---@field win_id number
---@field opts FloatWindowOptions
local UserInputWindow = {}
local class_mt = { __index = FloatWindow } -- inherit FloatWindow behavior too
setmetatable(UserInputWindow, class_mt)

--- Position the input box at the bottom of the editor, centered horizontally.
--- The chat window floats in the middle of the screen; this box sits at the bottom.
--- NOTE: defined with DOT (not colon) to match FloatWindow.window_config's signature,
--- which is invoked as `self.window_config(self.opts)`.
---@param opts FloatWindowOptions
---@return vim.api.keyset.win_config
function UserInputWindow.window_config(opts)
    local win_width = math.ceil((opts.width_ratio or 0.6) * vim.o.columns)
    local win_height = INPUT_HEIGHT
    local left_is_at_col = math.floor((vim.o.columns - win_width) / 2)
    -- leave a 1-row margin from the very bottom of the editor
    local bottom_row = math.max(0, vim.o.lines - win_height - 1)
    return {
        row = bottom_row,
        col = left_is_at_col,
        width = win_width,
        height = win_height,
        relative = "editor",
        style = "minimal",
        border = "single",
    }
end

---@return UserInputWindow
function UserInputWindow:new()
    ---@type FloatWindowOptions
    local opts = {
        width_ratio = 0.6,
        filetype = "text",
        buffer_name = "AskAgentInput",
    }

    -- NOTE: pass `UserInputWindow` as the receiver so the created instance inherits
    -- from this class (giving us the bottom-positioned window_config), not FloatWindow.
    return FloatWindow.new(UserInputWindow, opts)
end

--- Close the input window but keep its buffer (so typed text is preserved).
function UserInputWindow:hide()
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        vim.api.nvim_win_close(self.win_id, true)
        self.win_id = nil
    end
end

return UserInputWindow
