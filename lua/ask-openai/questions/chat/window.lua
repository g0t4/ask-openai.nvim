local LinesBuilder = require("ask-openai.questions.lines_builder")
local BufferController = require("ask-openai.questions.buffers")
local HLGroups = require("ask-openai.hlgroups")
local FloatWindow = require("ask-openai.helpers.float_window")

---@class ChatWindow
---@field buffer_number number
---@field buffer BufferController
---@field winid number
local ChatWindow = {}

function ChatWindow:new()
    self = setmetatable({}, { __index = ChatWindow })

    local listed_buffer = false
    local scratch_buffer = true -- must be scratch, otherwise have to save contents or trash it on exit
    local buffer_number = vim.api.nvim_create_buf(listed_buffer, scratch_buffer)

    self.buffer_number = buffer_number
    self.buffer = BufferController:new(self.buffer_number)
    vim.api.nvim_buf_set_name(self.buffer_number, 'Question Response')

    -- * buffer local keymaps
    vim.keymap.set('n', '<leader>c', function() self:clear() end, { buffer = self.buffer_number, desc = "clear the chat window, and eventually the message history" })

    return self
end

function ChatWindow:open()
    ---@type FloatWindowOptions
    local opts = { width_ratio = 0.5, height_ratio = 0.8, filetype = "markdown" }

    local win = vim.api.nvim_open_win(self.buffer_number, true, FloatWindow.centered_window(opts))
    self.winid = win

    -- set FileType after creating window, otherwise the default wrap option (vim.o.wrap) will override any ftplugin mods to wrap (and the same for other window-local options like wrap)
    vim.api.nvim_set_option_value('filetype', opts.filetype, { buf = self.buffer_number })

    -- manually trigger LSP attach, b/c scratch buffers are normally not auto attached
    local client = vim.lsp.get_clients({ name = "ask_language_server" })[1]
    if client then vim.lsp.buf_attach_client(self.buffer_number, client.id) end

    -- * make window resizable
    local gid = vim.api.nvim_create_augroup("ChatWindow_" .. win, { clear = true })
    vim.api.nvim_create_autocmd("VimResized", {
        group = gid,
        callback = function()
            if not vim.api.nvim_win_is_valid(win) then return end
            vim.api.nvim_win_set_config(win, FloatWindow.centered_window(opts))
        end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = gid,
        pattern = tostring(win),
        callback = function()
            -- when THIS window closes, drop its autocmds
            pcall(vim.api.nvim_del_augroup_by_id, gid)
        end,
        once = true,
    })
end

function ChatWindow:ensure_open()
    if self.winid and vim.api.nvim_win_is_valid(self.winid) then
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
