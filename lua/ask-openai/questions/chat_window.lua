local BufferController = require("ask-openai.questions.buffers")

---@class ChatWindow
---@field buffer_number number
---@field buffer BufferController
---@field winid number
local ChatWindow = {}

function ChatWindow:new()
    self = setmetatable({}, { __index = ChatWindow })

    local listed_buffer = false
    -- must be scratch, otherwise have to save contents or trash it on exit
    local scratch_buffer = true
    local bufnr = vim.api.nvim_create_buf(listed_buffer, scratch_buffer)

    self.buffer_number = bufnr
    self.buffer = BufferController:new(self.buffer_number)
    vim.api.nvim_buf_set_name(self.buffer_number, 'Question Response')
    -- buffer local keymaps
    -- PRN use <LocalLeader>?
    vim.keymap.set('n', '<leader>c', function() self:clear() end, { buffer = self.buffer_number, desc = "clear the chat window, and eventually the message history" })

    return self
end

local function centered_window()
    -- TODO? minimum width? basically a point at which the window is allowed to cover more than 50% wide and 80% tall
    local win_height = math.ceil(0.8 * vim.o.lines)
    local win_width = math.ceil(0.5 * vim.o.columns)
    local top_is_at_row = math.floor((vim.o.lines - win_height) / 2)
    local left_is_at_col = math.floor((vim.o.columns - win_width) / 2)
    return {
        relative = "editor",
        width = win_width,
        height = win_height,
        row = top_is_at_row,
        col = left_is_at_col,
        style = "minimal",
        border = "single",
    }
end

function ChatWindow:open()
    local win = vim.api.nvim_open_win(self.buffer_number, true, centered_window())
    self.winid = win

    -- set FileType after creating window, otherwise the default wrap option (vim.o.wrap) will override any ftplugin mods to wrap (and the same for other window-local options like wrap)
    vim.api.nvim_set_option_value('filetype', 'markdown', { buf = self.buffer_number })

    -- manually trigger LSP attach, b/c scratch buffers are normally not auto attached
    local client = vim.lsp.get_clients({ name = "ask_language_server" })[1]
    if client then vim.lsp.buf_attach_client(self.buffer_number, client.id) end

    local gid = vim.api.nvim_create_augroup("ChatWindow_" .. win, { clear = true })

    vim.api.nvim_create_autocmd("VimResized", {
        group = gid,
        callback = function()
            if not vim.api.nvim_win_is_valid(win) then return end
            vim.api.nvim_win_set_config(win, centered_window())
        end,
    })

    -- when THIS window closes, drop its autocmds
    vim.api.nvim_create_autocmd("WinClosed", {
        group = gid,
        pattern = tostring(win),
        callback = function()
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

    -- TODO put this in a opened event handler for the window
    -- set manual folding so I can fold line ranges (i.e. reasoning sections) automatically!
    --  else my default of treesitter will kick in
    vim.o.foldmethod = "manual"
    vim.o.foldenable = true
    vim.o.foldlevel = 0
end

function ChatWindow:explain_error(text)
    -- TODO add extmarks with red background like I did in rewrite/inline.lua => displayer class
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
