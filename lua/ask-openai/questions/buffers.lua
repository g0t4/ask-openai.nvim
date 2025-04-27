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

    self:scroll_cursor_to_end_of_buffer()
end

function BufferController:scroll_cursor_to_end_of_buffer()
    vim.cmd("normal! G")
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

    -- todo should I only scroll if the new content goes past the last line? i.e. if more than one line in new_lines?
    --   would that have any performance impact?
    self:scroll_cursor_to_end_of_buffer()
end

function BufferController:get_lines_after(line_number_0based)
    -- I can extend this to a line range later... for now I just want all lines after a line #
    local lines = vim.api.nvim_buf_get_lines(self.buffer_number, line_number_0based, -1, false)
    return table.concat(lines, "\n")
end

return BufferController
