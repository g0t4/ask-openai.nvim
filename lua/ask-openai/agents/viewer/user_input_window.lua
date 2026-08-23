local FloatWindow = require("ask-openai.helpers.float_window")
local layout = require("ask-openai.agents.viewer.layout")
local HLGroups = require("ask-openai.hlgroups")

---@class UserInputWindow : FloatWindow
---@field buffer_number number
---@field win_id number
---@field opts FloatWindowOptions
local UserInputWindow = {}
local class_mt = { __index = FloatWindow } -- inherit FloatWindow behavior too
setmetatable(UserInputWindow, class_mt)

--- Position the input box at the bottom of the usable float area, full width.
--- The chat (history) window fills the space above it (see window.lua), so the
--- two together use all available rows without overlapping. Its bottom border
--- lands in the command line (hidden), leaving only the shared top border.
--- NOTE: defined with DOT (not colon) to match FloatWindow.window_config's signature,
--- which is invoked as `self.window_config(self.opts)`.
---@param opts FloatWindowOptions
---@return vim.api.keyset.win_config
function UserInputWindow.window_config(opts)
    local win_width = vim.o.columns
    local win_height = layout.input_height()
    local bottom_row = math.max(0, layout.editor_height() - win_height)
    return {
        row = bottom_row,
        col = 0,
        width = win_width,
        height = win_height,
        relative = "editor",
        style = "minimal",
        -- empty border cells => no visible box around the input box
        border = { "", "", "", "", "", "", "", "" },
        -- distinct background so the input box stands out from the chat viewer above it
        winhighlight = "NormalFloat:" .. HLGroups.USER_INPUT,
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
    local instance = FloatWindow.new(UserInputWindow, opts)

    -- Scratch buffers are not automatically attached, but we want LSP features (tool calls, semantic_grep telescope)
    local client = vim.lsp.get_clients({ name = "ask_language_server" })[1]
    if client then
        vim.lsp.buf_attach_client(instance.buffer_number, client.id)
    end

    return instance
end

--- Close the input window but keep its buffer (so typed text is preserved).
function UserInputWindow:hide()
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        vim.api.nvim_win_close(self.win_id, true)
        self.win_id = nil
    end
end

return UserInputWindow
