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

local function split_lines_to_table(text)
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

    local lines = split_lines_to_table(self.prediction)
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

function Prediction:accept_first_line()
    -- FYI instead of splitting every time... could make a class that buffers into line splits for me! use a table of chunks until hit \n... flush to the next line and start accumulating next line, etc
    local lines = split_lines_to_table(self.prediction)
    if #lines == 0 then
        return
    end

    -- PRN add integration testing of these buffer/cursor interactions

    -- * insert first line
    local first_line = table.remove(lines, 1) -- mostly just change this to accept 1+ words/lines
    local cursor = get_cursor_position()

    self.disable_cursor_moved = true

    local BLANK_LINE = "" -- essential
    local inserted_lines = { first_line, BLANK_LINE }
    self:insert_text_at_cursor(cursor, inserted_lines)
    local controller = CursorController:new()
    controller:move_cursor_after_insert(cursor, inserted_lines)

    -- PRIOR CURSOR move
    --    vim.api.nvim_win_set_cursor(0, { cursor.line_base1 + 1, 0 }) -- (1,0)-indexed (row,col) -- **
    --    - move to start of next line (every time)... b/c then I can naturally accept the next line!
    --
    --    1. moving down takes my eyes with the cursor to read the next line (from its start)
    --    2. and then being on that line means my calculations all work out (if I wound up at end of current line then I'd have to do smth to go down (without losing prediction)...
    --
    --    BTW the blank line is important...
    --    - w/o it, you end up eating one line below per accepted line...
    --      b/c new code is INSERTED into existing (cursor) line
    --    - so the new blank just adds the next line to insert into (one at a time)
    --
    -- TODO get testing in place, there are some edge cases (i.e. whey I insert a blank line) that I really want to document!

    -- * remove first line from prediction
    self.prediction = table.concat(lines, "\n")
    self:redraw_extmarks()
end

function Prediction:accept_first_word()
    local lines = split_lines_to_table(self.prediction)
    if #lines == 0 then
        return
    end
    log:warn("lines", vim.inspect(lines))

    -- FYI! leave this hot mess for now... you're re-learning the edge cases... that's a good thing!
    --    DO NOT CLEAN THIS UNTIL YOU REALLY ARE SURE YOU KNOW IT IS WORKING WELL with CursorController
    --     and you are happy with fixes for edge cases (i.e. wrap lines)
    --
    -- PRN add integration testing of these buffer/cursor interactions

    local _, word_end = lines[1]:find("[_%w]+") -- find first word (range)
    local first_word
    local inserted_lines = {}
    local BLANK_LINE = ""
    if word_end == nil then
        -- *1 one non-word left
        log:warn("  *1 rest of line is non-word char(s) (matches all of it) => wrap to next line")

        -- FYI SCENARIO TO TEST: delete } or all of {} on the {} above and the line after (or not)
        --    get prediction that spans to next line(s)
        --    this works b/c the last chars on the line are non-words
        --    so you'll match it and then w/o the BLANK_LINE here the line won't wrap!

        first_word = lines[1]
        inserted_lines = { first_word, BLANK_LINE }
        lines[1] = ""
    else
        first_word = lines[1]:sub(1, word_end) -- pull that word out
        inserted_lines = { first_word }

        if first_word == lines[1] then
            -- *2 one word left
            log:warn("  *3 rest of line is one word (no non-word chars left) => wrap to next line")

            -- FYI SCENARIO TO TEST:
            --   delete the "else" line (on its own line) above and the line after it... gen two+ line
            --   go into insert mode right where else's e is at
            --   then alt+right on else hits this scenario

            -- FYI line ending => needs to insert blank line!
            -- TODO don't add BLANK_LINE if #lines == 1 ? this is my critique of what I had before!
            inserted_lines = { first_word, BLANK_LINE }
            lines[1] = ""
        else
            -- *3 matched next word (line has more words after this)
            -- strip first_word:
            lines[1] = lines[1]:sub(word_end + 1) or "" -- shouldn't need `or ""`
        end
    end
    log:warn("  first_word", vim.inspect(first_word))
    log:warn("  lines[1]", vim.inspect(lines[1]))
    log:warn("  inserted_lines", vim.inspect(inserted_lines))

    -- * insert first word
    local cursor = get_cursor_position()
    self.disable_cursor_moved = true
    self:insert_text_at_cursor(cursor, inserted_lines)
    local controller = CursorController:new()
    controller:move_cursor_after_insert(cursor, inserted_lines)

    -- * update prediction with remainder
    self.prediction = table.concat(lines, "\n")
    log:warn("  self.prediction", vim.inspect(self.prediction))
    self:redraw_extmarks()
end

function Prediction:accept_all()
    local lines = split_lines_to_table(self.prediction)
    if #lines == 0 then
        return
    end

    local cursor = get_cursor_position()

    self.disable_cursor_moved = true
    local inserted_lines = lines
    self:insert_text_at_cursor(cursor, inserted_lines)
    local controller = CursorController:new()
    controller:move_cursor_after_insert(cursor, inserted_lines)

    -- -- TODO cursor column move position calculation has two scenarios:
    -- -- 1. inserting text on current line only => cursor moves relative to its current position + len(accepted text) => so this is why I have issues with accept all on a single line prediction! b/c it doesn't include cursor.col_base0 below!
    -- -- 2. inserting multiple lines => in this case, cursor moves to last line of inserted text, right after last inserted character (IOTW length of last linei == #lines[#lines])
    -- -- cursor should stop at end of inserted text
    -- local new_cursor_col_base0 = #lines[#lines]
    -- local new_cursor_line_base1 = cursor.line_base1 + #lines - 1
    -- vim.api.nvim_win_set_cursor(0, { new_cursor_line_base1, new_cursor_col_base0 }) -- (1,0)-indexed (row,col)
    -- -- TODO review cursor line movement... in different scenarios
    -- -- 1. insert text into current line only:
    -- --    a. if middle of current line, stay on current line
    -- --    b. if accept to end of current line, stay or go to next line?
    -- -- 2. if multiline insert...
    -- --    a. if last line has no existing text after it... then stay or go to next line?
    -- --    b. if last line has existing text after it... then probably stay on that line?
    -- -- ** I am leaning toward let's just move cursor to end of accepted text (not ever go beyond that to next line, at least for accept all)... that seems to be my intent too (minus the column bug)
    -- -- FYI this is a good first example to add some testing!

    self.prediction = "" -- strip all lines from the prediction (and update it)
    self:redraw_extmarks()

    -- PRN? mark fully accepted?
    -- SIGNAL TO handlers to generate next prediction? or not?
end

function Prediction:IDEA_accept_line_with_replace_current_line()
    -- gptoss often recommends text that has full line (not just new text)... if I had accept line and replace existing line motion... that would make it far less painful!
    --
    -- alternative would be to do diffs and strip common parts... so I can show just the new text as if the model didn't screw up!
    -- - this would actually work as a basis for edit predictions (not just FIM) ... could start small with one line editing only
end

return Prediction
