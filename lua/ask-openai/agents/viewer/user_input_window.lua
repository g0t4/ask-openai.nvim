local FloatWindow = require("ask-openai.helpers.float_window")
local layout = require("ask-openai.agents.viewer.layout")
local HLGroups = require("ask-openai.hlgroups")

---@class UserInputWindow : FloatWindow
---@field buffer_number number
---@field window_id number
---@field opts FloatWindowOptions
local UserInputWindow = {}
setmetatable(UserInputWindow, { __index = FloatWindow })
UserInputWindow.__index = UserInputWindow -- only needed if UserInputWindow is not a singleton, so instances can access its methods and fields
-- rule:
--   look for key on table `instance[key]` directly
--   look for key in __index
--   look for key in get_metatable(obj).__index
--   FYI best way to see prototype chain (if you will) is to print it in neovim `:lua foo` => shows each level of _index and its methods/fields

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
function UserInputWindow.new()
    ---@type FloatWindowOptions
    local opts = {
        filetype = "text",
        buffer_name = "AskAgentInput",
        window_id = nil, -- not set until FloatWindow opened
    }

    -- NOTE: pass `UserInputWindow` as the receiver so the created instance inherits
    -- from this class (giving us the bottom-positioned window_config), not FloatWindow.
    -- UserInputWindow is technicall a singleton here, so it is kinda odd to have a `.new()` for it
    local instance = FloatWindow.new(UserInputWindow, opts)

    -- Scratch buffers are not automatically attached, but we want LSP features (tool calls, semantic_grep telescope)
    local client = vim.lsp.get_clients({ name = "ask_ls" })[1]
    if client then
        vim.lsp.buf_attach_client(instance.buffer_number, client.id)
    end

    return instance
end

--- Close the input window but keep its buffer (so typed text is preserved).
function UserInputWindow:hide()
    if self.window_id and vim.api.nvim_win_is_valid(self.window_id) then
        pcall(vim.api.nvim_win_close, self.window_id, true)
    end
    self.window_id = nil
end

return UserInputWindow
