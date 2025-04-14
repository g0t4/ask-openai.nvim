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

return BufferController
