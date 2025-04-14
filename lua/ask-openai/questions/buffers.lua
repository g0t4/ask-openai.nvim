local log = require("ask-openai.prediction.logger").predictions()
---@class BufferController
---@field buffer_number number
local BufferController = {}

function BufferController:new(buffer_number)
    self = setmetatable({}, { __index = BufferController })
    self.buffer_number = buffer_number
    return self
end

function BufferController:append(text)
    local num_lines = vim.api.nvim_buf_line_count(self.buffer_number)
    local last_line = vim.api.nvim_buf_get_lines(self.buffer_number, num_lines - 1, num_lines, false)[1]
    local replace_lines = vim.split(last_line .. text .. "\n", "\n")
    vim.api.nvim_buf_set_lines(self.buffer_number, num_lines - 1, num_lines, false, replace_lines)

    -- move cursor/scroll to end of buffer
    lines = vim.api.nvim_buf_line_count(self.buffer_number)
    vim.api.nvim_win_set_cursor(0, { lines, 0 })
end

function BufferController:clear()
    vim.api.nvim_buf_set_lines(self.buffer_number, 0, -1, false, {})
end

function BufferController:get_line_count()
    return vim.api.nvim_buf_line_count(self.buffer_number)
end

function BufferController:get_cursor_line_number_0based()
    local cursor = vim.api.nvim_win_get_cursor(0)
    return cursor[1] - 1
end

function BufferController:replace_lines_after(line_number, new_lines)
    -- TODO if perf is an issue, I could easily keep last lines, do a diff and patch only changed lines
    --   that said, given this is just the current request... that basically is a coarse grain diff
    vim.api.nvim_buf_set_lines(self.buffer_number, line_number, -1, false, new_lines)
end

function BufferController:get_last_paragraph()
    -- TODO add unit tests of this
    --   TODO notably handle whether or not this should include the empty line above a paragraph (when there is one, i.e. not when only paragraph is on line 1
    --        FYI could remove empty line before/after paragraph
    vim.cmd("normal! G{") -- find line with start of last paragraph
    -- FYI G{ will move in the buffer, which is fine b/c if typing a question, s/b at bottom already
    local line_number_0based = self:get_cursor_line_number_0based()
    local lines = vim.api.nvim_buf_get_lines(self.buffer_number, line_number_0based, -1, false)
    local paragraph = table.concat(lines, "\n")
    vim.cmd("normal! G$o") -- move back to end of buffer, add new line below
    -- PRN if I need line numbers, I could return those as 2nd/3rd return values
    return paragraph
end

return BufferController
