local LinesBuilder = require("ask-openai.questions.lines_builder")
local BufferController = require("ask-openai.questions.buffers")
local HLGroups = require("ask-openai.hlgroups")
local FloatWindow = require("ask-openai.helpers.float_window")

---@class ChatWindow : FloatWindow
---@field buffer_number number
---@field buffer BufferController
---@field win_id number
local ChatWindow = {}
local class_mt = { __index = FloatWindow } -- inherit FloatWindow behavior too
setmetatable(ChatWindow, class_mt)

function ChatWindow:new()
    ---@type FloatWindowOptions
    local opts = { width_ratio = 0.5, height_ratio = 0.8, filetype = "markdown" }

    local instance_mt = { __index = self } -- FYI self is likely ChatWindow here
    local lines = nil
    local instance = setmetatable(FloatWindow:new(lines, opts), instance_mt)

    instance.buffer = BufferController:new(instance.buffer_number)
    vim.api.nvim_buf_set_name(instance.buffer_number, 'Question Response')

    -- * buffer local keymaps
    vim.keymap.set('n', '<leader>c', function() instance:clear() end, { buffer = instance.buffer_number, desc = "clear the chat window, and eventually the message history" })

    -- manually trigger LSP attach, b/c scratch buffers are normally not auto attached
    local client = vim.lsp.get_clients({ name = "ask_language_server" })[1]
    if client then vim.lsp.buf_attach_client(self.buffer_number, client.id) end

    return instance
end

function ChatWindow:open()
    -- TODO GET RID OF THIS?
end

function ChatWindow:ensure_open()
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        return
    end
    self:open()

    -- * folding options
    vim.opt_local.foldmethod = "expr"
    vim.opt_local.foldexpr = "v:lua.MyChatWindowFolding()"
    vim.opt_local.foldenable = true
    vim.opt_local.foldlevel = 0 -- CLOSE all folds with higher number, thus 0 == ALL (equiv to zM => foldenable + foldlevel=0)
end

---@type ExplainError
function ChatWindow:explain_error(text)
    local lines = LinesBuilder:new()
    lines:create_marks_namespace()
    lines:append_styled_text(text, HLGroups.EXPLAIN_ERROR)
    lines:append_blank_line()
    self:append_styled_lines(lines)
end

---@param lines LinesBuilder
function ChatWindow:append_styled_lines(lines)
    self.buffer:append_styled_lines(lines)
end

--- clear the window contents only (not message history)
function ChatWindow:clear()
    self.buffer:clear()
end

function ChatWindow:close()
    vim.api.nvim_win_close(0, true)
end

return ChatWindow
