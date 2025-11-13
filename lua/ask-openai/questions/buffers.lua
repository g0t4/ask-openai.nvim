local log = require("ask-openai.logs.logger").predictions()
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

function BufferController:get_cursor_line_number_0indexed()
    local cursor = vim.api.nvim_win_get_cursor(0)
    return cursor[1] - 1
end

local ns = vim.api.nvim_create_namespace('test_colors_chat')

function BufferController:replace_lines_after(line_number, new_lines)
    -- TODO allow passing extmarks to go with the lines to add so it is all one operation before they show
    vim.api.nvim_buf_call(self.buffer_number, function()
        -- "atomic" so no flickering b/w adding lines and extmarks

        -- replace all lines from line_number to end of file
        vim.api.nvim_buf_set_lines(self.buffer_number, line_number, -1, false, new_lines)

        vim.api.nvim_buf_clear_namespace(self.buffer_number, ns, 0, -1)

        vim.api.nvim_buf_set_extmark(self.buffer_number, ns,
            line_number,
            0,
            {
                hl_group = 'Added',
                end_line = line_number + #new_lines,
                end_col  = 0,
            }
        )
    end)

    self:scroll_cursor_to_end_of_buffer()
end

function BufferController:get_lines_after(line_number_0indexed)
    -- I can extend this to a line range later... for now I just want all lines after a line #
    local lines = vim.api.nvim_buf_get_lines(self.buffer_number, line_number_0indexed, -1, false)
    return table.concat(lines, "\n")
end

return BufferController
