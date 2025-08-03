local Prediction = {}
local uv = vim.uv

local log = require("ask-openai.logs.logger").predictions()

local hlgroup = "AskPrediction"

function Prediction:new()
    local prediction = {}
    -- id was originaly intended to track current prediction and not let past predictions write to extmarks (for example)
    prediction.id = uv.hrtime() -- might not need id if I can use object reference instead, we will see (id is helpful if I need to roundtrip identity outside lua process)
    -- (nanosecond) time based s/b sufficient, esp b/c there should only ever be one prediction at a time.. even if multiple in short time (b/c of keystrokes, there is gonna be 1ms or so between them at most)

    -- PRN prediction per buffer (only when not having this becomes a hassle)
    prediction.buffer = 0 -- 0 = CURRENT_BUFFER

    prediction.namespace_id = vim.api.nvim_create_namespace("ask-predictions")
    -- ?? keep \n to differentiate lines ? or map to some sort of object model (lines at least... and maybe tokenize the lines)
    prediction.prediction = ""
    prediction.extmarks = {}
    prediction.paused = false
    prediction.buffered_chunks = ""
    prediction.abandoned = false -- PRN could be a prediction state? IF NEEDED
    prediction.disable_cursor_moved = false
    return setmetatable(prediction, { __index = Prediction })
end

function Prediction:add_chunk_to_prediction(chunk)
    if self.paused then
        self.buffered_chunks = self.buffered_chunks .. chunk
        return
    end

    self.prediction = self.prediction .. chunk
    self:redraw_extmarks()
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
    -- clear from 0 to -1 => entire buffer

    local original_row_1indexed, original_col = unpack(vim.api.nvim_win_get_cursor(0)) -- (1,0)-indexed #s... aka original_row starts at 1, original_col starts at 0
    local original_row = original_row_1indexed - 1 -- 0-indexed now

    if self.prediction == nil then
        print("unexpected... prediction is nil?")
        return
    end

    local lines = split_lines_to_table(self.prediction)
    if #lines == 0 then
        return
    end

    local first_line = { { table.remove(lines, 1), hlgroup } } -- can add hlgroup too

    local virt_lines = {} -- FYI is a 3D array,  array of (lines like first_line format above)
    -- local virt_lines_example = { { { "line1 ..." } }, { { "line2 ..." } } }
    -- each line has an array of strings to add to the line and each string can have its own hlgroup (that is why)
    for i, line in ipairs(lines) do
        -- FYI can add hlgroup as second item { line, hlgroup }
        table.insert(virt_lines, { { line, hlgroup } })
    end

    vim.api.nvim_buf_set_extmark(self.buffer, self.namespace_id, original_row, original_col,
        -- FYI, row,col are 0-indexed! ARGH FML
        {
            virt_text = first_line,
            virt_lines = virt_lines,
            -- inline? for my testing? if I am at end of line it won't matter
            virt_text_pos = "inline",
        })
end

function Prediction:clear_extmarks()
    -- clear from 0 to -1 => entire buffer
    vim.api.nvim_buf_clear_namespace(self.buffer, self.namespace_id, 0, -1)
end

function Prediction:pause_new_chunks()
    --
    -- pause means stop showing new chunks
    --    make sure to accept what is shown (if accepted after pause)
    --    which means new chunks (after paused) need to be:
    --      buffered
    --      or discarded
    --
    self.paused = true
end

function Prediction:resume_new_chunks()
    self.paused = false
    self.prediction = self.prediction .. self.buffered_chunks
    -- add the buffered chunks to the prediction so far (and clear out the buffer)
    self.buffered_chunks = ""
    -- TODO vim.schedule? not in background AFAIK, so.. no
    self:redraw_extmarks()
end

function Prediction:mark_as_abandoned()
    self.abandoned = true
end

function Prediction:mark_generation_finished()
    self.generated = true -- TODO status field
end

function Prediction:mark_generation_failed()
    self.mark_generation_failed = true
    -- LEAVE GENERATION visible so I can see it to troubleshoot (cursor move / exit insert mode will clear it)
    --
    -- user can trigger a new prediction
    -- basically behaves just like finishing a prediction
end

function Prediction:accept_first_line()
    if not self.generated then
        -- IT WORKS GREAT! though I always waited for first line to be done... its gonna be an issue mid line :)
        --    IN FACT IT IS BEAUTIFUL!! accept while its writing!! YESSSS
        -- what if someone tries to do this while completion is still generating?
        log:warn("WARNING - accepting completion while still generating, might not be an issue... will see")
        -- IIAC only one thing can run at a time so it might be ok?
    end

    local lines = split_lines_to_table(self.prediction)
    if #lines == 0 then
        return
    end

    local first_line = table.remove(lines, 1) -- mostly just change this to accept 1+ words/lines

    -- insert first line into document
    local original_row_1indexed, original_col = unpack(vim.api.nvim_win_get_cursor(0)) -- (1,0)-indexed #s... aka original_row starts at 1, original_col starts at 0
    local original_row = original_row_1indexed - 1 -- 0-indexed now

    self.disable_cursor_moved = true
    -- INSERT ONLY.. so (row,col)=>(row,col) covers 0 characters (thus this inserts w/o replacing)
    vim.api.nvim_buf_set_text(self.buffer, original_row, original_col, original_row, original_col, { first_line, "" })
    vim.api.nvim_win_set_cursor(0, { original_row_1indexed + 1, 0 }) -- (1,0)-indexed (row,col)

    self.prediction = table.concat(lines, "\n") -- strip that first line then from the prediction (and update it)
    self:redraw_extmarks()
end

function Prediction:accept_first_word()
    if not self.generated then
        -- IT WORKS GREAT! though I always waited for first line to be done... its gonna be an issue mid line :)
        --    IN FACT IT IS BEAUTIFUL!! accept while its writing!! YESSSS
        -- what if someone tries to do this while completion is still generating?
        log:warn("WARNING - accepting completion while still generating, might not be an issue... will see")
        -- IIAC only one thing can run at a time so it might be ok?
    end

    local lines = split_lines_to_table(self.prediction)
    if #lines == 0 then
        return
    end

    local _, word_end = lines[1]:find("[_%w]+") -- find first word (range)
    if word_end == nil then
        -- log:trace("no words in first line, accepting entire line")
        self:accept_first_line()
        return
    end

    local first_word = lines[1]:sub(1, word_end) or ""
    if first_word == lines[1] then
        -- BTW can get blank line (with ' ' or ' \n' ... go right after a function definition and add a new line, or two... and if your cursor stays above the new lines, right below func signature, it will often suggest a blank line there - qwen2.5-coder:7b does anyways)
        -- rest of word, then use accept line
        -- log:trace("next word is last word for line, take it all")
        self:accept_first_line()
        return
    end
    -- strip first_word:
    lines[1] = lines[1]:sub(word_end + 1) or "" -- shouldn't need `or ""`

    -- insert first word into document
    local original_row_1indexed, original_col = unpack(vim.api.nvim_win_get_cursor(0)) -- (1,0)-indexed #s... aka original_row starts at 1, original_col starts at 0
    local original_row = original_row_1indexed - 1 -- 0-indexed now

    self.disable_cursor_moved = true
    -- INSERT ONLY.. so (row,col)=>(row,col) covers 0 characters (thus this inserts w/o replacing)
    vim.api.nvim_buf_set_text(self.buffer, original_row, original_col, original_row, original_col, { first_word })
    vim.api.nvim_win_set_cursor(0, { original_row_1indexed, original_col + #first_word }) -- (1,0)-indexed (row,col)

    self.prediction = table.concat(lines, "\n") -- strip that first line then from the prediction (and update it)
    self:redraw_extmarks()
end

function Prediction:accept_all()
    local lines = split_lines_to_table(self.prediction)
    if #lines == 0 then
        return
    end

    local original_row_1indexed, original_col = unpack(vim.api.nvim_win_get_cursor(0)) -- (1,0)-indexed #s... aka original_row starts at 1, original_col starts at 0
    local original_row = original_row_1indexed - 1 -- 0-indexed now

    self.disable_cursor_moved = true
    vim.api.nvim_buf_set_text(self.buffer, original_row, original_col, original_row, original_col, lines)

    -- cursor should stop at end of inserted text
    local last_col = #lines[#lines] --
    local last_row = original_row_1indexed + #lines - 1
    vim.api.nvim_win_set_cursor(0, { last_row, last_col }) -- (1,0)-indexed (row,col)

    self.prediction = "" -- strip all lines from the prediction (and update it)
    self:redraw_extmarks()
    -- TODO mark fully accepted?
    -- SIGNAL TO handlers to generate next prediction? or not?
end

return Prediction
