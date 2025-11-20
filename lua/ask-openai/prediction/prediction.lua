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
    return setmetatable(self, { __index = Prediction })
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

function Prediction:redraw_extmarks()
    self:clear_extmarks()

    local cursor_line_base1, cursor_col_base0 = unpack(vim.api.nvim_win_get_cursor(0))
    local cursor_line_base0 = cursor_line_base1 - 1

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

    vim.api.nvim_buf_set_extmark(self.buffer, extmarks_ns_id, cursor_line_base0, cursor_col_base0, -- row & col are 0-indexed
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

function Prediction:accept_first_line()
    -- FYI instead of splitting every time... could make a class that buffers into line splits for me! use a table of chunks until hit \n... flush to the next line and start accumulating next line, etc
    local lines = split_lines_to_table(self.prediction)
    if #lines == 0 then
        return
    end

    -- PRN add integration testing of these buffer/cursor interactions

    -- * insert first line
    local first_line = table.remove(lines, 1) -- mostly just change this to accept 1+ words/lines
    local cursor_line_base1, cursor_col_base0 = unpack(vim.api.nvim_win_get_cursor(0))
    local cursor_line_base0 = cursor_line_base1 - 1 -- 0-indexed now

    self.disable_cursor_moved = true
    -- INSERT ONLY.. so (row,col)=>(row,col) covers 0 characters (thus this inserts w/o replacing)
    vim.api.nvim_buf_set_text(self.buffer, cursor_line_base0, cursor_col_base0, cursor_line_base0, cursor_col_base0, { first_line, "" })
    vim.api.nvim_win_set_cursor(0, { cursor_line_base1 + 1, 0 }) -- (1,0)-indexed (row,col)

    -- * remove first line from prediction
    self.prediction = table.concat(lines, "\n")
    self:redraw_extmarks()
end

function Prediction:accept_first_word()
    local lines = split_lines_to_table(self.prediction)
    if #lines == 0 then
        return
    end

    -- PRN add integration testing of these buffer/cursor interactions

    local _, word_end = lines[1]:find("[_%w]+") -- find first word (range)
    if word_end == nil then
        -- PRN test scenario so I can experiment with how this feels!
        self:accept_first_line()
        return
    end

    local first_word = lines[1]:sub(1, word_end) or ""
    if first_word == lines[1] then
        -- PRN test scenario
        self:accept_first_line()
        return
    end
    -- strip first_word:
    lines[1] = lines[1]:sub(word_end + 1) or "" -- shouldn't need `or ""`

    -- insert first word into document
    local cursor_line_base1, cursor_col_base0 = unpack(vim.api.nvim_win_get_cursor(0))
    local cursor_line_base0 = cursor_line_base1 - 1

    self.disable_cursor_moved = true
    -- TODO reduce duplication here with inserting... this is in every accept handler... how about make a PredictionAcceptor class? (tested too): insert text, move cursor, etc?
    -- INSERT ONLY.. so (row,col)=>(row,col) covers 0 characters (thus this inserts w/o replacing)
    vim.api.nvim_buf_set_text(self.buffer, cursor_line_base0, cursor_col_base0, cursor_line_base0, cursor_col_base0, { first_word })
    vim.api.nvim_win_set_cursor(0, { cursor_line_base1, cursor_col_base0 + #first_word }) -- (1,0)-indexed (row,col)

    self.prediction = table.concat(lines, "\n") -- strip that first line then from the prediction (and update it)
    self:redraw_extmarks()
end

function Prediction:accept_all()
    local lines = split_lines_to_table(self.prediction)
    if #lines == 0 then
        return
    end

    local cursor_line_base1, cursor_col_base0 = unpack(vim.api.nvim_win_get_cursor(0))
    local cursor_line_base0 = cursor_line_base1 - 1

    self.disable_cursor_moved = true
    vim.api.nvim_buf_set_text(self.buffer, cursor_line_base0, cursor_col_base0, cursor_line_base0, cursor_col_base0, lines)

    -- TODO cursor column move position calculation has two scenarios:
    -- 1. inserting text on current line only => cursor moves relative to its current position + len(accepted text) => so this is why I have issues with accept all on a single line prediction! b/c it doesn't include cursor_col_base0 below!
    -- 2. inserting multiple lines => in this case, cursor moves to last line of inserted text, right after last inserted character (IOTW length of last linei == #lines[#lines])
    -- cursor should stop at end of inserted text
    local last_col_0indexed = #lines[#lines]
    local last_row_1indexed = cursor_line_base1 + #lines - 1
    vim.api.nvim_win_set_cursor(0, { last_row_1indexed, last_col_0indexed }) -- (1,0)-indexed (row,col)
    -- TODO review cursor row movement... in different scenarios
    -- 1. insert text into current line only:
    --    a. if middle of current line, stay on current line
    --    b. if accept to end of current line, stay or go to next line?
    -- 2. if multiline insert...
    --    a. if last line has no existing text after it... then stay or go to next line?
    --    b. if last line has existing text after it... then probably stay on that line?
    -- ** I am leaning toward let's just move cursor to end of accepted text (not ever go beyond that to next line, at least for accept all)... that seems to be my intent too (minus the column bug)
    -- FYI this is a good first example to add some testing!

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
