local BufferController = require("ask-openai.questions.buffers")

---@class ChatWindow
---@field buffer_number number
---@field buffer BufferController
---@field winid number
local ChatWindow = {}

function ChatWindow:new()
    self = setmetatable({}, { __index = ChatWindow })
    local bufnr = vim.api.nvim_create_buf(false, true)
    self.buffer_number = bufnr
    self.buffer = BufferController:new(self.buffer_number)
    vim.api.nvim_buf_set_name(self.buffer_number, 'Question Response')
    -- buffer local keymaps
    -- PRN use <LocalLeader>?
    vim.keymap.set('n', '<leader>c', function() self:clear() end, { buffer = self.buffer_number, desc = "clear the chat window, and eventually the message history" })
    return self
end

function ChatWindow:open()
    local height_percent = 80
    local width_percent = 50

    local screen_lines = vim.api.nvim_get_option_value('lines', {})
    local screen_columns = vim.api.nvim_get_option_value('columns', {})
    local win_height = math.ceil(height_percent / 100 * screen_lines)
    local win_width = math.ceil(width_percent / 100 * screen_columns)
    local top_is_at_row = screen_lines / 2 - win_height / 2
    local left_is_at_col = screen_columns / 2 - win_width / 2
    self.winid = vim.api.nvim_open_win(self.buffer_number, true, {
        relative = 'editor',
        width = win_width,
        height = win_height,
        row = top_is_at_row,
        col = left_is_at_col,
        style = 'minimal',
        border = 'single'
    })
    -- set FileType after creating window, otherwise the default wrap option (vim.o.wrap) will override any ftplugin mods to wrap (and the same for other window-local options like wrap)
    vim.api.nvim_set_option_value('filetype', 'markdown', { buf = self.buffer_number })
end

function ChatWindow:ensure_open()
    if self.winid and vim.api.nvim_win_is_valid(self.winid) then
        return
    end
    self:open()
end

function ChatWindow:explain_error(text)
    -- TODO add extmarks for error too?
    self.buffer:append("## ERROR " .. tostring(text))
end

function ChatWindow:append(text)
    self.buffer:append(text)
end

function ChatWindow:clear()
    self.buffer:clear()
    -- TODO clear message history (how do I want to link that? did I finish follow up already?)
end

function ChatWindow:close()
    vim.api.nvim_win_close(0, true)
end

return ChatWindow
