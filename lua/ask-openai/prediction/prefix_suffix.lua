local log = require("ask-openai.logs.logger").predictions()

local IGNORE_BOUNDARIES = false
local M = {}

---@class Chunk
---@field i1_start_line integer
---@field i1_end_line integer
---@field lines string|string[] -- TODO lines array or text?
local Chunk = {}

function M.get_line_range(current_row, take_max_num_lines, buffer_line_count)
    -- FYI do not adjust for 0/1-indexed, assume all of these are in same 0/1-index
    --   only adjust when using nvim's line funcs

    local first_row = current_row - take_max_num_lines
    local last_row = current_row + take_max_num_lines
    if first_row < 0 then
        -- first row cannot < 0
        local extra_rows = -first_row
        first_row = 0

        -- expand end of range
        last_row = last_row + extra_rows
    end
    if last_row > buffer_line_count then
        -- last row cannot be > num_rows_total
        local extra_rows = last_row - buffer_line_count
        last_row = buffer_line_count

        -- add extra rows to start of range:
        first_row = first_row - extra_rows
        first_row = math.max(0, first_row)
        -- todo do I have to ensure > 0 ? for first_row
    end
    return first_row, last_row
end

---@return Chunk prefix, Chunk suffix
function M.get_prefix_suffix()
    -- presently, this only works with current buffer/window:
    local current_win_id = 0
    local current_bufnr = 0

    local cursor_line_1indexed, cursor_col_0indexed = unpack(vim.api.nvim_win_get_cursor(current_win_id)) -- (1,0)-indexed
    local cursor_line_0indexed = cursor_line_1indexed - 1 -- 0-indexed now

    local take_max_num_lines = 80
    local line_count = vim.api.nvim_buf_line_count(current_bufnr)
    local first_row, last_row = M.get_line_range(cursor_line_0indexed, take_max_num_lines, line_count)
    log:trace("first_row", first_row, "last_row", last_row, "cursor_line_0indexed", cursor_line_0indexed, "cursor_col_0indexed", cursor_col_0indexed)

    local current_line = vim.api.nvim_buf_get_lines(current_bufnr, cursor_line_0indexed, cursor_line_0indexed + 1, IGNORE_BOUNDARIES)[1] -- 0indexed, END-EXCLUSIVE
    log:trace("current_line", current_line)

    local before_is_thru_col = cursor_col_0indexed -- don't +1 b/c that would include the char under the cursor which goes after any typed/inserted chars
    -- test edge case: enter insert mode 'i' => type/paste char(s) => observe char under cursor position shifts right
    local current_line_before_split = current_line:sub(1, before_is_thru_col) -- sub is END-INCLUSIVE ("foobar"):sub(2,3) == "ob"
    log:trace("current_line_before (1 => " .. before_is_thru_col .. "): '" .. current_line_before_split .. "'")

    local after_starts_at_char_under_cursor = cursor_col_0indexed + 1 -- FYI cursor_col_0indexed, thus +1
    local current_line_after_split = current_line:sub(after_starts_at_char_under_cursor)
    log:trace("current_line_after (" .. after_starts_at_char_under_cursor .. " => end): '" .. current_line_after_split .. "'")

    local lines_before_current = vim.api.nvim_buf_get_lines(current_bufnr, first_row, cursor_line_0indexed, IGNORE_BOUNDARIES) -- 0indexed, END-EXCLUSIVE
    local document_prefix = table.concat(lines_before_current, "\n") .. "\n" .. current_line_before_split

    -- TODO edge cases for new line at end of current line? is that a concern
    local lines_after_current = vim.api.nvim_buf_get_lines(current_bufnr, cursor_line_0indexed + 1, last_row, IGNORE_BOUNDARIES) -- 0indexed END-EXCLUSIVE
    -- pass new lines verbatim so the model can understand line breaks (as well as indents) as-is!
    local document_suffix = current_line_after_split .. "\n" .. table.concat(lines_after_current, "\n")

    if log.is_verbose_enabled() then
        -- if in trace mode... combine document prefix and suffix and check if matches entire document:
        local entire_document = table.concat(vim.api.nvim_buf_get_lines(current_bufnr, first_row, last_row, IGNORE_BOUNDARIES), "\n")
        local combined = document_prefix .. document_suffix
        if entire_document ~= combined then
            -- trace mode, check if matches (otherwise may be incomplete or not in expected format)
            log:error("document mismatch: prefix+suffix != entire document")
            log:trace("diff\n", vim.diff(entire_document, combined))
        end
    end
    -- TODO convert to new Chunk type (w/ line #s so I can pass those to LSP to only skip lines in this range with RAG matching)
    return document_prefix, document_suffix
end

return M
