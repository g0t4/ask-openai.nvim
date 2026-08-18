local FloatWindow = require("ask-openai.helpers.float_window")
local layout = require("ask-openai.agents.viewer.layout")

---@class UserInputWindow : FloatWindow
---@field buffer_number number
---@field win_id number
---@field opts FloatWindowOptions
local UserInputWindow = {}
local class_mt = { __index = FloatWindow } -- inherit FloatWindow behavior too
setmetatable(UserInputWindow, class_mt)

--- Position the input box at the very bottom of the editor, full width.
--- The chat (history) window fills the space above it (see window.lua), so the
--- two together use all available lines without overlapping.
--- NOTE: defined with DOT (not colon) to match FloatWindow.window_config's signature,
--- which is invoked as `self.window_config(self.opts)`.
---@param opts FloatWindowOptions
---@return vim.api.keyset.win_config
function UserInputWindow.window_config(opts)
    local win_width = vim.o.columns
    local win_height = layout.INPUT_HEIGHT
    local bottom_row = math.max(0, vim.o.lines - win_height)
    return {
        row = bottom_row,
        col = 0,
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
