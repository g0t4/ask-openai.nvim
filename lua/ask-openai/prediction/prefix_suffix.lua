local log = require("ask-openai.logs.logger").predictions()

local IGNORE_BOUNDARIES = false
local M = {}

---@class Chunk
---@field i1_start_line integer
---@field i1_end_line integer
---@field lines string|string[] -- TODO lines array or text?
local Chunk = {}

--- Determine range of lines to take before/after cursor position.
--- Try taking X lines in both directions.
--- If one direction doesn't have X lines, try taking the difference from the other side.
function M.determine_line_range_base0(current_row_b0, take_num_lines_each_way, buffer_line_count)
    -- separate logic for finding range of lines to use as prefix/suffix
    -- - the math here can be off by a smidge and won't matter b/c separate code reads the lines
    -- - assuming cursor line stays in range, you're good to go

    -- FYI I am experimenting here with _b0 for base 0... leave this style for comparison until you feel super compelled to make everything the same

    local take_start_row_b0 = current_row_b0 - take_num_lines_each_way
    local take_end_row_b0 = current_row_b0 + take_num_lines_each_way
    if take_start_row_b0 < 0 then
        -- start row cannot be before first line!
        local unused_prefix_rows = -take_start_row_b0
        take_start_row_b0 = 0

        -- unused lines in prefix are added to possible suffix
        take_end_row_b0 = take_end_row_b0 + unused_prefix_rows
    end

    local last_row_num_b0 = buffer_line_count - 1
    if take_end_row_b0 > last_row_num_b0 then
        -- end row cannot be after last line!
        local unused_suffix_rows = take_end_row_b0 - buffer_line_count
        take_end_row_b0 = last_row_num_b0

        -- unused lines in suffix are added to possible prefix
        take_start_row_b0 = take_start_row_b0 - unused_suffix_rows
        take_start_row_b0 = math.max(0, take_start_row_b0)
    end
    return take_start_row_b0, take_end_row_b0
end

---@return Chunk prefix, Chunk suffix
function M.get_prefix_suffix(take_num_lines_each_way)
    take_num_lines_each_way = take_num_lines_each_way or 80
    -- presently, this only works with current buffer/window:
    local current_win_id = 0
    local current_bufnr = 0

    local cursor_line_base1, cursor_col_base0 = unpack(vim.api.nvim_win_get_cursor(current_win_id)) -- (1,0)-indexed
    local cursor_line_base0 = cursor_line_base1 - 1 -- 0-indexed now


    -- * READ LINES AROUND CURSOR LINE
    local line_count = vim.api.nvim_buf_line_count(current_bufnr)
    local take_start_row_base0, take_end_row_base0 = M.determine_line_range_base0(cursor_line_base0, take_num_lines_each_way, line_count)

    local cursor_row_text = vim.api.nvim_buf_get_lines(current_bufnr,
        -- 0indexed, END-EXCLUSIVE
        cursor_line_base0,
        cursor_line_base0 + 1, -- end is exclusive, thus + 1
        IGNORE_BOUNDARIES
    )[1]


    -- * PREFIX
    -- FYI prefix stops with column before cursor column
    local col_before_cursor_base1 = cursor_col_base0
    local cursor_row_text_before_cursor = cursor_row_text:sub(1, col_before_cursor_base1) -- 1-indexed, END-INCLUSIVE ("foobar"):sub(2,3) == "ob"

    local lines_before_cursor_line = vim.api.nvim_buf_get_lines(current_bufnr, take_start_row_base0, cursor_line_base0, IGNORE_BOUNDARIES) -- 0indexed, END-EXCLUSIVE

    local prefix_text = table.concat(lines_before_cursor_line, "\n") .. "\n" .. cursor_row_text_before_cursor


    -- * SUFFIX
    -- FYI char under the cursor is in the suffix
    local cursor_col_base1 = cursor_col_base0 + 1
    local cursor_row_text_cursor_plus = cursor_row_text:sub(cursor_col_base1) -- 1-indexed, END-INCLUSIVE

    -- TODO edge cases for new line at end of current line? is that a concern
    local lines_after_cursor_line = vim.api.nvim_buf_get_lines(current_bufnr,
        -- 0indexed END-EXCLUSIVE
        cursor_line_base0 + 1, -- start w/ line after cursor line
        take_end_row_base0 + 1, -- end is exclusive, thus + 1
        IGNORE_BOUNDARIES
    )

    local suffix_text = cursor_row_text_cursor_plus
        .. "\n" -- TODO! doesn't cursor row have a newline already? why am I adding that here?
        .. table.concat(lines_after_cursor_line, "\n")

    -- TODO convert to new Chunk type (w/ line #s so I can pass those to LSP to only skip lines in this range with RAG matching)
    return prefix_text, suffix_text
end

return M
