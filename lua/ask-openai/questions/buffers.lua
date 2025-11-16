local log = require("ask-openai.logs.logger").predictions()
local Fold = require("ask-openai.questions.fold")
require("ask-openai.prediction.context.inspect")

---@class BufferController
---@field buffer_number number
---@field folds Fold[]
local BufferController = {}

function BufferController:new(buffer_number)
    self = setmetatable({}, { __index = BufferController })
    self.buffer_number = buffer_number
    self.folds = {}
    return self
end

--- Split text on \n and append the lines to the end of the buffer
---@param text string
function BufferController:append_text(text)
    local new_lines = vim.split(text .. "\n", "\n") -- \n ensures a blank line after
    self:append_lines(new_lines)
end

--- Append a list of lines to the end of the buffer
---@param lines string[]
function BufferController:append_lines(lines)
    vim.api.nvim_buf_set_lines(self.buffer_number, -1, -1, false, lines)
    -- TODO update other nvim_buf_set_lines cases for insert and other operations to not need to replace when inserting (or similar)
    self:scroll_cursor_to_end_of_buffer()
end

function BufferController:append_blank_line()
    self:append_lines({ "" })
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

---@param lines LinesBuilder
function BufferController:append_lines_builder(lines)
    local start_line_base0 = self:get_line_count()
    if start_line_base0 == 1 then
        -- edge case, first line is not actually used in a new buffer (it's legit empty)
        start_line_base0 = 0
    end
    self:replace_lines_after(start_line_base0, lines)
end

---@param start_line_inclusive_base0 number
---@param lines LinesBuilder
function BufferController:replace_lines_after(start_line_inclusive_base0, lines)
    local with_lines = lines.turn_lines
    local marks = lines.marks
    local marks_ns_id = lines.marks_ns_id

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

            -- TODO   vim.opt.foldtext = "v:lua.MyFoldText()"
            --      summary text for the fold
            --      OR use extmarks to summarize
            --  TODO show "reasoning"
            --  PRN show thinking dots when it's WIP!
        end

        -- log:info("folding:")
        -- local line_count = vim.api.nvim_buf_line_count(self.buffer_number)
        -- for i = 0, line_count - 1 do
        --     log:info("  line[" .. i .. "] → " .. _G.MyChatWindowFoldingForLine(i))
        -- end
    end)

    self:scroll_cursor_to_end_of_buffer()
end

function BufferController:get_lines_after(line_number_0indexed)
    -- I can extend this to a line range later... for now I just want all lines after a line #
    local lines = vim.api.nvim_buf_get_lines(self.buffer_number, line_number_0indexed, -1, false)
    return table.concat(lines, "\n")
end

return BufferController
