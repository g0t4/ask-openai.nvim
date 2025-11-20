local dots = require("ask-openai.rewrites.thinking.dots")
local HLGroups = require("ask-openai.hlgroups")
local log = require("ask-openai.logs.logger").predictions()

---@class Prediction
---@field id integer
---@field buffer integer
---@field prediction string         # content streamed so far (excluding buffered chunks)
---@field extmarks table
---@field paused boolean
---@field buffered_chunks string    # chunks received while `paused`
---@field abandoned boolean         # user aborted prediction
---@field disable_cursor_moved boolean
---@field has_reasoning boolean
---@field private reasoning_chunks string[]
---@field start_time number
---@field generated boolean|nil
local Prediction = {}
local instance_metatable = { __index = Prediction }
local extmarks_ns_id = vim.api.nvim_create_namespace("ask-predictions")

---@return Prediction
function Prediction.new()
    local self = {} -- FYI after changing to self being a new instance per prediction... instead of all using Prediction singleton... I might have issues w/ cancel/abort/back2back predictions as I type... just keep that in mind

    -- id was originaly intended to track current prediction and not let past predictions write to extmarks (for example)
    self.id = vim.uv.hrtime() -- might not need id if I can use object reference instead, we will see (id is helpful if I need to roundtrip identity outside lua process)
    -- (nanosecond) time based s/b sufficient, esp b/c there should only ever be one prediction at a time.. even if multiple in short time (b/c of keystrokes, there is gonna be 1ms or so between them at most)

    self.buffer = 0 -- 0 == current buffer
    self.prediction = ""
    self.extmarks = {}
    self.paused = false
    self.buffered_chunks = ""
    self.abandoned = false
    self.disable_cursor_moved = false
    self.has_reasoning = false
    self.reasoning_chunks = {}
    self.start_time = os.time()
    setmetatable(self, instance_metatable)
    return self
end

function Prediction:add_chunk_to_prediction(chunk, reasoning_content)
    if self.paused then
        self.buffered_chunks = self.buffered_chunks .. chunk
        return
    end

    if chunk then
        self.prediction = self.prediction .. chunk
    end
    if reasoning_content then
        table.insert(self.reasoning_chunks, reasoning_content)
        self.has_reasoning = true
    end
    self:redraw_extmarks()
end

function Prediction:get_reasoning()
    return table.concat(self.reasoning_chunks, "")
end

function Prediction:any_chunks()
    return self.prediction and self.prediction ~= ""
        or self.buffered_chunks and self.buffered_chunks ~= ""
end

---@param text string
---@return string[] lines
local function split_lines(text)
    ---@type string[]
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    return lines
end

---@class CursorInfo
---@field line_base0 integer
---@field line_base1 integer
---@field col_base0 integer
---@field col_base1 integer

---@return CursorInfo
local function get_cursor_position()
    -- TODO make CursorController w/ method to calculate (and maybe even move) it by lines/cols!
    -- TODO move and use elsewhere too!
    local line_base1, col_base0 = unpack(vim.api.nvim_win_get_cursor(0)) -- (1,0)-indexed (row,col)
    return {
        line_base1 = line_base1,
        line_base0 = line_base1 - 1,
        col_base0 = col_base0,
        col_base1 = col_base0 + 1,
    }
end

function Prediction:redraw_extmarks()
    self:clear_extmarks()

    local cursor = get_cursor_position()

    if self.prediction == nil then
        print("unexpected... prediction is nil?")
        return
    end

    local lines = split_lines(self.prediction)
    if #lines == 0 then
        if not self.has_reasoning then
            return
        end
        lines = { dots:get_still_thinking_message(self.start_time) }
    end

    local first_line = { { table.remove(lines, 1), HLGroups.PREDICTION_TEXT } }

    local virt_lines = {}
    for i, line in ipairs(lines) do
        table.insert(virt_lines, { { line, HLGroups.PREDICTION_TEXT } })
    end

    vim.api.nvim_buf_set_extmark(self.buffer, extmarks_ns_id, cursor.line_base0, cursor.col_base0, -- 0-indexed
        {
            virt_text = first_line,
            virt_lines = virt_lines,
            virt_text_pos = "inline",
        })
end

function Prediction:clear_extmarks()
    vim.api.nvim_buf_clear_namespace(self.buffer, extmarks_ns_id, 0, -1)
end

function Prediction:pause_new_chunks()
    -- pause means stop showing new chunks (buffer new chunks)
    self.paused = true
end

function Prediction:resume_new_chunks()
    self.paused = false
    self.prediction = self.prediction .. self.buffered_chunks
    self.buffered_chunks = ""
    self:redraw_extmarks()
end

function Prediction:mark_as_abandoned()
    self.abandoned = true
end

function Prediction:mark_generation_finished()
    self.generated = true
end

function Prediction:mark_generation_failed()
    self.mark_generation_failed = true
end

---@param cursor CursorInfo
---@param lines string[]
function Prediction:insert_text_at_cursor(cursor, lines)
    -- TODO get_cursor_position() in here? (especially if I move the move logic here!)
    -- start = end = cursor position!
    vim.api.nvim_buf_set_text(self.buffer, cursor.line_base0, cursor.col_base0, cursor.line_base0, cursor.col_base0, lines)
end

local CursorController = require "ask-openai.prediction.cursor_controller"
local BLANK_LINE = ""

function Prediction:insert_accepted(lines)
    self.disable_cursor_moved = true
    local cursor = get_cursor_position()
    self:insert_text_at_cursor(cursor, lines)
    local controller = CursorController:new()
    controller:move_cursor_after_insert(cursor, lines)
end

function Prediction:accept_first_line()
    -- FYI instead of splitting every time... could make a class that buffers into line splits for me! use a table of chunks until hit \n... flush to the next line and start accumulating next line, etc
    local lines = split_lines(self.prediction)
    if #lines == 0 then
        return
    end

    -- PRN add integration testing of these buffer/cursor interactions

    -- * insert first line
    local first_line = table.remove(lines, 1)
    local inserted_lines = { first_line }
    if #lines > 0 then
        -- only wrap a line if there are more lines to accept!
        inserted_lines = { first_line, BLANK_LINE }

        -- BTW the blank line is important...
        -- - w/o it, you end up eating one line below per accepted line...
        --   b/c new code is INSERTED into existing (cursor) line
        -- - so the new blank just adds the next line to insert into (one at a time)
    end

    self:insert_accepted(inserted_lines)

    -- * update prediction
    self.prediction = table.concat(lines, "\n")
    self:redraw_extmarks()
end

function Prediction:accept_first_word()
    local lines = split_lines(self.prediction)
    if #lines == 0 then
        return
    end
    log:warn("lines", vim.inspect(lines))

    -- PRN add integration testing of these buffer/cursor interactions

    local _, word_end = lines[1]:find("[_%w]+") -- find first word (range)
    log:warn("  word_end", vim.inspect(word_end))
    local inserted_lines = {}

    local one_non_word_remains = word_end == nil
    local one_word_remains = word_end == #lines[1] -- word_end == # chars in line ==> full match!
    local matches_rest_of_line = one_non_word_remains or one_word_remains
    if matches_rest_of_line then
        log:warn("  one_non_word_remains", vim.inspect(one_non_word_remains))
        log:warn("  one_word_remains", vim.inspect(one_word_remains))

        -- FYI TEST SCENARIOS:
        -- identify one of each:
        -- 1. non-word: } or {}
        -- 2. word: end/else
        -- then, two cases each (to test finishing a line):
        --   - test accept on last word/non-word at end of line
        --   A. with no line after (does not insert blank line, right)
        --   B. with line after, inserts blank and propertly continues to accept on that next line
        --   redo the gen to get a useful scenario (often can get one word gens on lines that really only would have one word/non-word)

        -- take rest of line
        local first_word = lines[1]
        lines[1] = ""

        local last_predicted_line = #lines == 1
        if last_predicted_line then
            inserted_lines = { first_word }
        else
            inserted_lines = { first_word, BLANK_LINE }
        end
    else
        -- take next word only (not end of line)
        local first_word = lines[1]:sub(1, word_end)
        lines[1] = lines[1]:sub(word_end + 1)

        inserted_lines = { first_word }
    end
    log:warn("  lines[1]", vim.inspect(lines[1]))
    log:warn("  inserted_lines", vim.inspect(inserted_lines))

    self:insert_accepted(inserted_lines)

    -- * update prediction
    self.prediction = table.concat(lines, "\n")
    log:warn("  self.prediction", vim.inspect(self.prediction))
    self:redraw_extmarks()
end

function Prediction:accept_all()
    local lines = split_lines(self.prediction)
    if #lines == 0 then
        return
    end

    self:insert_accepted(lines)

    -- FYI KEY TEST SCENARIO: complete to end of generated text
    --   * easy b/c no partial accept... whatever the model generates, insert it
    --   MOVE cursor to end of inserted text:
    --   - same line as last char
    --   - no extra blank lines

    -- * clear prediction
    self.prediction = "" -- strip all lines from the prediction (and update it)
    self:redraw_extmarks()

    -- PRN? mark fully accepted?
    -- TODO? SIGNAL TO handlers to generate next prediction? or not? (same on other accepts if they take last part of prediction)
end

function Prediction:IDEA_accept_line_with_replace_current_line()
    -- gptoss often recommends text that has full line (not just new text)... if I had accept line and replace existing line motion... that would make it far less painful!
    --
    -- alternative would be to do diffs and strip common parts... so I can show just the new text as if the model didn't screw up!
    -- - this would actually work as a basis for edit predictions (not just FIM) ... could start small with one line editing only
end

return Prediction
