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

function BufferController:replace_lines_after(line_number_base0, with_lines, marks, marks_ns_id)
    vim.api.nvim_buf_call(self.buffer_number, function()
        -- "atomic" so no flickering b/w adding lines and extmarks

        -- replace all lines from line_number (offset for this conversation turn) to end of file
        vim.api.nvim_buf_set_lines(self.buffer_number, line_number_base0, -1, false, with_lines)

        vim.api.nvim_buf_clear_namespace(self.buffer_number, marks_ns_id, 0, -1)

        for i, mark in ipairs(marks or {}) do
            -- log:info("mark", vim.inspect(mark))
            vim.api.nvim_buf_set_extmark(self.buffer_number, marks_ns_id,
                mark.start_line_base0 + line_number_base0,
                mark.start_col_base0,
                {
                    hl_group = mark.hl_group,
                    end_line = mark.end_line_base0 + line_number_base0,
                    end_col  = mark.end_col_base0,
                }
            )

            -- TODO FIX FOLDING TO NOT BE SUCH A HACKY PIECE OF SHIT (lol)
            --
            local more_than_one_line = mark.end_line_base0 > mark.start_line_base0 + 1
            if mark.fold and more_than_one_line then
                local fold_start_line_base0 = mark.start_line_base0 + line_number_base0 + 1
                -- delete fold(s)??
                vim.cmd(string.format(
                    -- translation => jump cursor to start line, zD => G (cursor back to end of file)
                    -- FYI the cursor movement is why this is not reliable! I would need to wait to confirm the cursor is moved before proceeding?
                    "silent! %d normal! zD; G",
                    fold_start_line_base0))

                -- add new fold
                vim.cmd(string.format(
                    "silent! %d,%dfold",
                    fold_start_line_base0,
                    mark.end_line_base0 + line_number_base0
                ))
            end
        end
    end)


    self:scroll_cursor_to_end_of_buffer()
end

function BufferController:get_lines_after(line_number_0indexed)
    -- I can extend this to a line range later... for now I just want all lines after a line #
    local lines = vim.api.nvim_buf_get_lines(self.buffer_number, line_number_0indexed, -1, false)
    return table.concat(lines, "\n")
end

return BufferController
