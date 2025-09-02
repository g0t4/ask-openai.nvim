local log = require("ask-openai.logs.logger").predictions()

local IGNORE_BOUNDARIES = false
local M = {}

---@class Chunk
---@field i1_start_line integer
---@field i1_end_line integer
---@field lines string|string[] -- TODO lines array or text?
local Chunk = {}

function M.get_line_range(current_row, allow_lines, total_lines_in_doc)
    -- FYI do not adjust for 0/1-indexed, assume all of these are in same 0/1-index
    --   only adjust when using nvim's line funcs

    local first_row = current_row - allow_lines
    local last_row = current_row + allow_lines
    if first_row < 0 then
        -- first row cannot < 0
        local extra_rows = -first_row
        first_row = 0

        -- expand end of range
        last_row = last_row + extra_rows
    end
    if last_row > total_lines_in_doc then
        -- last row cannot be > num_rows_total
        local extra_rows = last_row - total_lines_in_doc
        last_row = total_lines_in_doc

        -- add extra rows to start of range:
        first_row = first_row - extra_rows
        first_row = math.max(0, first_row)
        -- todo do I have to ensure > 0 ? for first_row
    end
    return first_row, last_row
end

---@param buffer_number integer
---@return Chunk prefix, Chunk suffix
function M.get_prefix_suffix(buffer_number)
    local current_window_id = 0 -- ONLY if needed, lookup: vim.fn.win_findbuf(bufnr) and take first?
    local original_row_1indexed, original_col = unpack(vim.api.nvim_win_get_cursor(current_window_id)) -- (1,0)-indexed
    local original_row_0indexed = original_row_1indexed - 1 -- 0-indexed now

    local allow_lines = 80
    local num_rows_total = vim.api.nvim_buf_line_count(buffer_number)
    -- TODO test for 0indexed vs 1indexed indexing in get_line_range (I know you can get a number past end of document but that works out given get_lines is END-EXCLUSIVE
    local first_row, last_row = M.get_line_range(original_row_0indexed, allow_lines, num_rows_total)
    log:trace("first_row", first_row, "last_row", last_row, "original_row_0indexed", original_row_0indexed, "original_col", original_col)

    local current_line = vim.api.nvim_buf_get_lines(buffer_number, original_row_0indexed, original_row_0indexed + 1, IGNORE_BOUNDARIES)[1]
    -- get_lines is END-EXCLUSIVE, 0-indexed
    log:trace("current_line", current_line)

    local before_is_thru_col = original_col -- original_col is 0-indexed, but don't +1 b/c that would include the char under the cursor which goes after any typed/inserted chars
    -- test edge case: enter insert mode 'i' => type/paste char(s) => observe char under cursor position shifts right
    local current_line_before_split = current_line:sub(1, before_is_thru_col) -- sub is END-INCLUSIVE ("foobar"):sub(2,3) == "ob"
    log:trace("current_line_before (1 => " .. before_is_thru_col .. "): '" .. current_line_before_split .. "'")

    local after_starts_at_char_under_cursor = original_col + 1 -- FYI original_col is 0-indexed, thus +1
    local current_line_after_split = current_line:sub(after_starts_at_char_under_cursor)
    log:trace("current_line_after (" .. after_starts_at_char_under_cursor .. " => end): '" .. current_line_after_split .. "'")

    local lines_before_current = vim.api.nvim_buf_get_lines(buffer_number, first_row, original_row_0indexed, IGNORE_BOUNDARIES) -- 0indexed, END-EXCLUSIVE
    local document_prefix = table.concat(lines_before_current, "\n") .. "\n" .. current_line_before_split

    -- TODO edge cases for new line at end of current line? is that a concern
    local lines_after_current = vim.api.nvim_buf_get_lines(buffer_number, original_row_0indexed + 1, last_row, IGNORE_BOUNDARIES) -- 0indexed END-EXCLUSIVE
    -- pass new lines verbatim so the model can understand line breaks (as well as indents) as-is!
    local document_suffix = current_line_after_split .. "\n" .. table.concat(lines_after_current, "\n")

    if log.is_verbose_enabled() then
        -- if in trace mode... combine document prefix and suffix and check if matches entire document:
        local entire_document = table.concat(vim.api.nvim_buf_get_lines(buffer_number, first_row, last_row, IGNORE_BOUNDARIES), "\n")
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
