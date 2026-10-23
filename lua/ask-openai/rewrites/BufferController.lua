local log = require("devtools.logs.logger").universal()
local Fold = require("ask-openai.agents.viewer.fold")
require("ask-openai.frontends.context.inspect")

---This entire class operates on 0-indexed row and column positions
---   or if that seems wrong I'll go to all 1-indexed
---Also intended to hide away complexities in nvim_ apis
---  esp the need to track window ids, buffer #s, etc
---@class BufferController0Indexed
---@field buffer_number integer
---@field win_id? integer -- window displaying this buffer (for cursor/scroll ops) -- TODO please move away from doing window operations on the buffer... move them to the WindowController0Indexed and let it call into this BufferController0Indexed when it needs to
---@field folds Fold[]
local BufferController0Indexed = {}
BufferController0Indexed.__index = BufferController0Indexed

---@param buffer_number integer
function BufferController0Indexed.for_buffer(buffer_number)
    local instance = setmetatable({}, BufferController0Indexed)
    instance.buffer_number = buffer_number
    instance.win_id = nil
    instance.folds = {}
    return instance
end

function BufferController0Indexed:buftype()
    return vim.bo[self.buffer_number].buftype
end

function BufferController0Indexed:filetype()
    return vim.bo[self.buffer_number].filetype
end

function BufferController0Indexed:file_name()
    return vim.api.nvim_buf_get_name(self.buffer_number)
end

function BufferController0Indexed:get_all_lines()
    -- FYI add/reshape the line access method to new scenarios that you actually use
    -- i.e. maybe add
    --    get_lines_from()
    --    get_lines_before()
    --    get_lines_in_range()

    return vim.api.nvim_buf_get_lines(self.buffer_number, 0, -1, true)
end

-- TODO! merge w/ other BufferController0Indexed (which I believe is mostly using 0 indexed now?)
--   TODO! also it has styled LinesBuilder support!
--   TODO! BTW... LinesBuilder probably overlaps with some of what Displayer does (w.r.t. styling extmarks)

--- does not include the end line #
---@param start_row integer 0-indexed
---@param end_row_exclusive integer 0-indexed
function BufferController0Indexed:get_lines(start_row, end_row_exclusive)
    -- TODO should I decide on end-inclusive or end-exclusive for ALL operations on BufferController0Indexed?
    --   if so which is more common in nvim APIs?
    --   * end-exclusive used by nvim_buf_get_lines
    -- PRN turn off strict indexing (allow clamp to start/end?)
    return vim.api.nvim_buf_get_lines(self.buffer_number, start_row, end_row_exclusive, true)
end

--- instead of leaving it ambiguous as to what node, lets by clear:
--- - tied to a specific buffer (buffer_number)
--- - tied to a specific position (row, column) - args
---@param row integer 0-indexed
---@param column integer 0-indexed
function BufferController0Indexed:get_node_at_position(row, column)
    return vim.treesitter
        .get_node({
            bufnr = self.buffer_number,
            pos = { row, column },
        })
    -- FTR get_node requires both bufnr and pos
    --   however it will use current buffer
    --   and current window if no bufnr specified
    -- Part of the reason to wrap this interaction is to
    --   make the parameters explicit
    --   and convenient (i.e. class tracks buffer number)
end

function BufferController0Indexed:set_text(text)
    local lines = vim.split(text, "\n")
    self:replace_lines(0, -1, lines)
end

---@param start_row_base0 integer 0-indexed, set start=end to insert new_lines
---@param end_row_inclusive_base0 integer 0-indexed, end-EXCLUSIV
---@param new_lines string[]
function BufferController0Indexed:replace_lines(start_row_base0, end_row_inclusive_base0, new_lines)
    -- TODO! likely replace this with BufferController0Indexed:replace_with_styled_lines_after (even if this is just plaintext)
    --   TODO! in fact, I could make this into a replace_plaintext_lines()
    -- log:info(vim.inspect({ start_row_base0 = start_row_base0, end_row_inclusive_base0 = end_row_inclusive_base0, }))
    if end_row_inclusive_base0 >= self:num_lines() then
        -- FYI this happens when testing fake prediction if you trigger it near the end of the buffer
        --   and the fake prediction is longer than the rest of the buffer
        log:error('end_row is past end of buffer, clamping to end of buffer.. should not happen IRL, only in testing')
        end_row_inclusive_base0 = self:num_lines() - 1
    end
    -- TODO why not use nvim_buf_set_lines??
    --   right now I am just replacing lines anyways!
    -- vim.api.nvim_buf_set_lines(
    vim.api.nvim_buf_set_text(self.buffer_number,
        -- indexing is 0 based
        start_row_base0, 0, -- 0 means first column
        end_row_inclusive_base0, -1, -- -1 means through the last column of the end_row
        new_lines)
    -- PRN tests:
    -- 1. selection through end of file (last line) => linewise visual mode, also maybe char wise visual mode
    --    - make sure last line is replaced
    --    - bug that caused seemingly duplicated last line (b/c not replaced, so regenerated unchanged => duplicates it)
end

--- inherently base1
function BufferController0Indexed:num_lines()
    return vim.api.nvim_buf_line_count(self.buffer_number)
end

--- Resolve the window currently displaying this buffer, preferring the tracked
--- owning window. Returns nil when the buffer isn't shown in any window so
--- callers must NOT fall back to operating on the *current* (focused) window.
---@return integer|nil
function BufferController0Indexed:get_window_id()
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        return self.win_id
    end
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win_id)
            and vim.api.nvim_win_get_buf(win_id) == self.buffer_number then
            return win_id
        end
    end
    return nil
end

--- Scroll the buffer to the end. Uses a window displaying this buffer (the
--- owning window when valid) so streaming content stays pinned to the bottom
--- even when another window (e.g. the user input box) has focus. Never scrolls
--- the current/focused window, so a redraw can't steal the user's typing cursor.
function BufferController0Indexed:scroll_cursor_to_end_of_buffer()
    -- TODO THIS BELONGS ON WINDOW NOT BUFFER
    local win_id = self:get_window_id()
    if not win_id then
        return
    end
    local last_line_base1 = vim.api.nvim_buf_line_count(self.buffer_number)
    vim.api.nvim_win_set_cursor(win_id, { last_line_base1, 0 })
end

function BufferController0Indexed:clear()
    vim.api.nvim_buf_set_lines(self.buffer_number, 0, -1, false, {})
end

function BufferController0Indexed:get_line_count()
    return vim.api.nvim_buf_line_count(self.buffer_number)
end

function BufferController0Indexed:get_cursor_line_number_0indexed()
    local win_id = self:get_window_id() or 0 -- 0 == current window (read-only here)
    local cursor = vim.api.nvim_win_get_cursor(win_id)
    return cursor[1] - 1
end

---@param lines LinesBuilder
function BufferController0Indexed:append_styled_lines(lines)
    local start_line_base0 = self:get_line_count()
    if start_line_base0 == 1 then
        -- edge case: an empty buffer's single line is a phantom empty line
        -- that should be replaced (start at 0). But a single *real* line
        -- should have new lines appended after it (start at 1).
        local buffer_is_empty = self:get_lines_from(0) == ""
        if buffer_is_empty then
            -- * phatom line ==> start at zero
            start_line_base0 = 0
        end
    end
    self:replace_with_styled_lines_after(start_line_base0, lines)
end

---@param start_line_inclusive_base0 number
---@param lines LinesBuilder
function BufferController0Indexed:replace_with_styled_lines_after(start_line_inclusive_base0, lines)
    local with_lines = lines.turn_lines
    -- log:error("with_lines", table.concat(with_lines, "\n"))

    local marks = lines.marks
    local marks_ns_id = lines.marks_ns_id

    -- FYI start_line offset is mostly important for styling extmarks/folds/etc
    local start_line_inclusive_base1 = start_line_inclusive_base0 + 1
    -- log:info(string.format("start_line_inclusive_base1 %d", start_line_inclusive_base1))

    vim.api.nvim_buf_call(self.buffer_number, function()
        -- "atomic" so no flickering b/w adding lines and extmarks

        -- ** ALTER FOLD RANGES FIRST (before modifying lines)
        -- 1. remove folds on lines being replaced
        local keep_folds = vim.iter(self.folds)
            :filter(function(fold)
                return fold.end_line_base1 < start_line_inclusive_base1
                -- FYI no folds should partially overlap (thus just use end)
            end):totable()
        self.folds = keep_folds

        -- --   * 2a. TESTING explicit fold at start of each turn
        -- --   * do not do this and add from marks (one or other)
        -- -- force always 3 lines to be folded (assuming at least 3 lines):
        -- self.folds = { Fold:new(start_line_inclusive_base1, math.min(#with_lines, 3) + start_line_inclusive_base1) }
        -- log:info("fold values", inspect_repr(self.folds))

        --   * 2b. add new fold range (BEFORE replacing lines)
        for i, mark in ipairs(marks or {}) do
            -- FYI ORDER MATTERS:
            -- because you are algorithmically setting folds with expr, adjust your ranges FIRST (before adding lines)
            --   b/c expr is evaluated after adding them! (so fold ranges must exist in advance)
            --   think of this as logical folds
            -- CAVEAT: if you go back to MANUALLY folding lines you'd need that to come AFTER adding the new lines
            --   cannot create a fold on lines that don't exist!
            --   think of this as physical folds
            -- *** IF YOU DO NOT CAREFULLY CONSIDER WHEN FOLDS ARE DEFINED:
            --   - folds will appear messed up / partial
            --   - frustrated chasing bugs in your fold logic that don't exist... when it's just timing!
            if mark.fold then
                local fold_start_line_base1 = mark.start_line_base0 + start_line_inclusive_base0 + 1
                local fold_end_line_base1 = mark.end_line_base0 + start_line_inclusive_base0 -- inclusive end so don't add 1 to get base1
                local fold = Fold:new(fold_start_line_base1, fold_end_line_base1)
                table.insert(self.folds, fold)
            end
        end

        -- replace all lines from line_number (offset for this conversation turn) to end of file
        vim.api.nvim_buf_set_lines(self.buffer_number, start_line_inclusive_base0, -1, false, with_lines)

        vim.api.nvim_buf_clear_namespace(self.buffer_number, marks_ns_id, 0, -1)

        -- * set extmarks (after lines replaced)
        for i, mark in ipairs(marks or {}) do
            vim.api.nvim_buf_set_extmark(self.buffer_number, marks_ns_id,
                mark.start_line_base0 + start_line_inclusive_base0,
                mark.start_col_base0,
                {
                    hl_group = mark.hl_group,
                    end_line = mark.end_line_base0 + start_line_inclusive_base0,
                    end_col  = mark.end_col_base0,
                }
            )
        end

        -- -- -- * add extmarks for <br> to virtually split line
        -- -- TODO do overhead testing of this plus surrounding redo logic on every token
        -- --   TODO if overhead is too steep, consider buffering tokens until every Nth token, OR maybe per line?
        -- --    per line should be pefectly fine!
        -- --    could even do it dynamic like first 5 lines, do it per token, after 10 lines wait for full lines thereafter...
        -- --    that way short completions don't appear laggy
        -- --    while also not redrawing every token for long completions where the token by token is not relevant
        -- --    and line by line might be a more smooth rendering
        -- --
        -- --  FYI there are possible cases where I wouldn't want to show a split
        -- --   i.e. verbatim reproduction of text in some scenario that has <br> in it...
        -- --   wait and see if any situation arises and if so roll this back
        -- --   I could forbid <br> in system prompt, but I hate the idea attention distractions... so, no
        -- --   worse case remove this and leave the <br> and move on with life
        -- --   PRN how common is this?
        -- for line_number_base1, line in ipairs(with_lines) do
        --     local search_start_col1 = 1
        --     while true do
        --         local start_col1, end_col1 = line:find("<br>", search_start_col1, true) -- find is 1-based column #s
        --         if not start_col1 then
        --             break
        --         end
        --         log:info("FOUND br", line, start_col1, end_col1)
        --         local col_base0 = start_col1 - 1
        --         vim.api.nvim_buf_set_extmark(
        --             self.buffer_number,
        --             marks_ns_id,
        --             start_line_inclusive_base0 + (line_number_base1 - 1), -- 0‑based
        --             col_base0, -- 0-based
        --             {
        --                 hl_group = "AskOpenAIBRTag",
        --                 -- show a zero‑width virtual text so the line is visually split
        --                 virt_text = { { "", "NonText" } },
        --                 virt_text_pos = "overlay",
        --             }
        --         )
        --         -- continue searching after this <br>
        --         search_start_col1 = end_col1 + 1
        --     end
        -- end

        -- log:info("folding:")
        -- local line_count = vim.api.nvim_buf_line_count(self.buffer_number)
        -- for i = 0, line_count - 1 do
        --     log:info("  line[" .. i .. "] → " .. _G.MyAgentWindowFoldingForLine(i))
        -- end
    end)

    self:scroll_cursor_to_end_of_buffer()
end

function BufferController0Indexed:get_lines_from(line_number_0indexed)
    -- I can extend this to a line range later... for now I just want all lines from a line # (inclusive) to the end
    local lines = vim.api.nvim_buf_get_lines(self.buffer_number, line_number_0indexed, -1, false)
    return table.concat(lines, "\n")
end

return BufferController0Indexed
