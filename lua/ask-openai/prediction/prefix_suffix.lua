local log = require("ask-openai.logs.logger").predictions()

local IGNORE_BOUNDARIES = false
local M = {}

---@class Chunk
---@field i1_start_line integer
---@field i1_end_line integer
---@field lines string|string[] -- TODO lines array or text?
local Chunk = {}

--- Determine range of lines to take before/after cursor position
function M.determine_line_range_base0(current_row_b0, take_num_lines_each_way, buffer_line_count)
    -- reminder... buffer_line_count is a count, so it does not have a base!

    local take_start_row_b0 = current_row_b0 - take_num_lines_each_way
    local take_end_row_b0 = current_row_b0 + take_num_lines_each_way
    if take_start_row_b0 < 0 then
        -- start row cannot be before first line!
        local unused_prefix_rows = -take_start_row_b0
        take_start_row_b0 = 0

        -- unused lines in prefix, thus expand possible suffix
        take_end_row_b0 = take_end_row_b0 + unused_prefix_rows
    end

    local last_line_base0 = buffer_line_count - 1
    if take_end_row_b0 > last_line_base0 then
        -- end row cannot be after last line!
        local unused_suffix_rows = take_end_row_b0 - buffer_line_count
        take_end_row_b0 = last_line_base0

        -- unused lines in suffix, try expanding prefix
        take_start_row_b0 = take_start_row_b0 - unused_suffix_rows
        take_start_row_b0 = math.max(0, take_start_row_b0)
    end
    return take_start_row_b0, take_end_row_b0
end

---@return Chunk prefix, Chunk suffix
function M.get_prefix_suffix()
    -- presently, this only works with current buffer/window:
    local current_win_id = 0
    local current_bufnr = 0

    local cursor_line_base1, cursor_col_base0 = unpack(vim.api.nvim_win_get_cursor(current_win_id)) -- (1,0)-indexed
    local cursor_line_base0 = cursor_line_base1 - 1 -- 0-indexed now

    local take_num_lines_each_way = 80
    local line_count = vim.api.nvim_buf_line_count(current_bufnr)
    local take_start_row_base0, take_end_row_base0 = M.determine_line_range_base0(cursor_line_base0, take_num_lines_each_way, line_count)

    local current_line = vim.api.nvim_buf_get_lines(current_bufnr,
        cursor_line_base0,
        cursor_line_base0 + 1, -- end is exclusive, thus + 1
        IGNORE_BOUNDARIES
    )[1] -- 0indexed, END-EXCLUSIVE

    local before_is_thru_col = cursor_col_base0 -- don't +1 b/c that would include the char under the cursor which goes after any typed/inserted chars
    -- test edge case: enter insert mode 'i' => type/paste char(s) => observe char under cursor position shifts right
    local current_line_before_split = current_line:sub(1, before_is_thru_col) -- sub is END-INCLUSIVE ("foobar"):sub(2,3) == "ob"

    local after_starts_at_char_under_cursor = cursor_col_base0 + 1 -- FYI cursor_col_0indexed, thus +1
    local current_line_after_split = current_line:sub(after_starts_at_char_under_cursor)

    local lines_before_current = vim.api.nvim_buf_get_lines(current_bufnr, take_start_row_base0, cursor_line_base0, IGNORE_BOUNDARIES) -- 0indexed, END-EXCLUSIVE
    local document_prefix = table.concat(lines_before_current, "\n") .. "\n" .. current_line_before_split

    -- TODO edge cases for new line at end of current line? is that a concern
    local lines_after_current = vim.api.nvim_buf_get_lines(current_bufnr,
        cursor_line_base0 + 1, -- start w/ line after cursor line
        take_end_row_base0 + 1, -- END-exclusive, thus add one to end row b/c we want the end row included
        IGNORE_BOUNDARIES
    ) -- 0indexed END-EXCLUSIVE

    -- pass new lines verbatim so the model can understand line breaks (as well as indents) as-is!
    local document_suffix = current_line_after_split .. "\n" .. table.concat(lines_after_current, "\n")

    -- TODO convert to new Chunk type (w/ line #s so I can pass those to LSP to only skip lines in this range with RAG matching)
    return document_prefix, document_suffix
end

return M
