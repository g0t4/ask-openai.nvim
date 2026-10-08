local dots = require("ask-openai.frontends.thinking.dots")
local HLGroups = require("ask-openai.hlgroups")
local log = require("devtools.logs.logger").universal()
local CursorController = require "ask-openai.predictions.cursor_controller"
local FIMPerformance = require("ask-openai.predictions.fim_performance")
local markdown_strip = require("ask-openai.predictions.markdown_strip")
local edit_alignment = require("ask-openai.predictions.edit_alignment")

---@class Prediction
---@field id integer
---@field bufnr integer
---@field prediction string
---@field all_sses SseFieldsResult[]
---@field first_line: string
---@field rest_of_lines: string[]
---@field insertion_line_base0: integer? -- where the delta inserts (buffer line, 0-indexed)
---@field insertion_col_base0: integer?  -- where the delta inserts (buffer col, 0-indexed)
---@field has_duplicate_prefix: boolean
---@field has_prediction: boolean
---@field extmarks table
---@field abandoned boolean         # user aborted prediction
---@field skip_text_changed_from_accept_suggestion boolean
---@field failures string[]
---@field done boolean
---
---@field has_reasoning boolean
---@field private reasoning_chunks string[]
---@field private started_content boolean # once content is shown, don't regress back to reasoning
---
---@field start_time number
---@field performance FIMPerformance   # timing/lifecycle state for this prediction
---@field fim_request? CurlRequest
---
---@field rag_cancel? fun()          # cancels the in-flight RAG query
---
---@field apply_template_only boolean -- true means send FIM to /apply-template endpoint (not real FIM) and just log the prompt (saves me from running --verbose-prompt with llama-server which is heavy for all requests and not easily toggled)
---
local Prediction = {}
local instance_metatable = { __index = Prediction }
local extmarks_ns_id = vim.api.nvim_create_namespace("ask-universal")

---@alias PredictionParameters { bufnr: integer, apply_template_only: boolean, }

---@param params? PredictionParameters
---@return Prediction
function Prediction.new(params)
    local self = {} -- FYI after changing to self being a new instance per prediction... instead of all using Prediction singleton... I might have issues w/ cancel/abort/back2back predictions as I type... just keep that in mind

    -- id was originaly intended to track current prediction and not let past predictions write to extmarks (for example)
    self.id = vim.uv.hrtime() -- might not need id if I can use object reference instead, we will see (id is helpful if I need to roundtrip identity outside lua process)
    -- (nanosecond) time based s/b sufficient, esp b/c there should only ever be one prediction at a time.. even if multiple in short time (b/c of keystrokes, there is gonna be 1ms or so between them at most)
    log:info("new PREDICTION id=" .. self.id .. " bufnr=" .. params.bufnr)

    -- FYI AFAICT no timing benefits from using a StringBuffer vs string.__concat... just b/c of my requirement to have full string on every iteration
    -- see test code: lua/ask-openai/prediction/tests/benchmark/str_concat_vs_buffer.lua

    if params.bufnr == nil or params.bufnr == 0 then
        error("YOU MUST PASS BUFFER NUMBER (bufnr) when creating a prediction now")
    end
    self.bufnr = params.bufnr
    self.extmarks = {}
    self.abandoned = false
    self.skip_text_changed_from_accept_suggestion = false
    self.has_reasoning = false
    self.reasoning_chunks = {}
    self.started_content = false
    self.start_time = os.time()
    self.performance = FIMPerformance:new()
    self.prediction = ""
    self.all_sses = {}
    self.rag_cancel = nil
    self.failures = {}
    self.done = false

    params = params or {}
    self.apply_template_only = params.apply_template_only


    setmetatable(self, instance_metatable)
    return self
end

function Prediction:finalize_prediction()
    self.done = true
    -- A completion that is only a markdown fence (e.g. an empty code block)
    -- has no real content, so clear the ghost extmarks (and any reasoning).
    local is_empty = self.prediction == ""
    if not Prediction._is_markdown_buffer(self.bufnr) then
        is_empty = is_empty or markdown_strip.strip(self.prediction) == ""
    end
    if is_empty then
        -- hide reasoning... BTW this should probably be put into fix_fim_and_redraw_extmarks() so we have one way to handle all updates?
        self:clear_extmarks()
        -- ? should I add a visual cue to signal that there wasn't a failure?
    end
end

---@param sse_fields SseFieldsResult
function Prediction:add_chunk_sse(sse_fields)
    table.insert(self.all_sses, sse_fields)
    if sse_fields.content then
        self.prediction = self.prediction .. sse_fields.content
    end
    if sse_fields.reasoning_content then
        table.insert(self.reasoning_chunks, sse_fields.reasoning_content)
        self.has_reasoning = true
    end
    self:fix_fim_and_redraw_extmarks()
end

function Prediction:get_reasoning()
    return table.concat(self.reasoning_chunks, "")
end

function Prediction:any_chunks()
    return self.prediction and self.prediction ~= ""
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

---@param bufnr integer
---@return boolean
function Prediction._is_markdown_buffer(bufnr)
    return vim.bo[bufnr].filetype == "markdown"
end

function Prediction:fim_fixes()
    local controller = CursorController:new()
    local cursor = controller:get_cursor_position()

    -- * Strip markdown code fences models sometimes wrap completions in
    --   (```language ... ``` or `...`). Not in markdown files, where the
    --   fences are the intended content.
    local is_markdown = Prediction._is_markdown_buffer(self.bufnr)
    local prediction_text = self.prediction
    if not is_markdown then
        prediction_text = markdown_strip.strip(prediction_text)
    end

    -- * Align the completion against the buffer using the verbatim-anchor
    --   contract, extracting the delta and where it inserts. After a partial
    --   accept the remaining prediction is the raw delta (no anchor), so show
    --   it directly instead of re-aligning.
    local edit = nil
    if not is_markdown and not self.has_accepts then
        local buffer_lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
        edit = edit_alignment.align(prediction_text, buffer_lines, cursor.line_base0, cursor.col_base0)
    end

    if edit then
        -- Aligned: use the extracted delta and its insertion position.
        self.insertion_line_base0 = edit.insertion_line_base0
        self.insertion_col_base0 = edit.insertion_col_base0
        self.first_line = edit.insertion_lines[1] or ""
        self.rest_of_lines = {}
        for i = 2, #edit.insertion_lines do
            table.insert(self.rest_of_lines, edit.insertion_lines[i])
        end
        self.has_prediction = #edit.insertion_lines > 0
    elseif is_markdown or self.has_accepts then
        -- Show the prediction directly (markdown content, or the remaining delta
        -- after a partial accept).
        local lines = edit_alignment.split_lines(prediction_text)
        self.insertion_line_base0 = nil
        self.insertion_col_base0 = nil
        self.first_line = lines[1] or ""
        self.rest_of_lines = {}
        for i = 2, #lines do
            table.insert(self.rest_of_lines, lines[i])
        end
        self.has_prediction = prediction_text ~= "" and #lines > 0
    else
        -- Streaming and not yet aligned (the anchor line has not arrived): wait.
        self.insertion_line_base0 = nil
        self.insertion_col_base0 = nil
        self.first_line = ""
        self.rest_of_lines = {}
        self.has_prediction = false
    end

    if self.has_prediction then
        self.started_content = true
    end
    return
end

function Prediction:fix_fim_and_redraw_extmarks()
    self:clear_extmarks()

    local controller = CursorController:new()
    local cursor = controller:get_cursor_position()

    if self.prediction == nil then
        print("unexpected... prediction is nil?")
        return
    end

    -- * show failures above the cursorline
    if self.failures then
        -- currently only one failure message but I designed this to handle more than one
        local virt_lines = {}
        for _, failure in ipairs(self.failures) do
            local lines = split_lines(failure)
            for _, line in ipairs(lines) do
                table.insert(virt_lines, { { line, HLGroups.EXPLAIN_ERROR } })
            end
        end
        self.extmarks.failures = vim.api.nvim_buf_set_extmark(
            self.bufnr,
            extmarks_ns_id,
            cursor.line_base0,
            -- TODO if we only match part of prefix... we shouldn't highlight all of it! rare but still support this?
            0, -- start from beginning of line
            {
                virt_lines_above = true,
                virt_lines = virt_lines,
                -- hl_eol = false,
            }
        )
        -- allow to continue showing prediction even if a failure is present
    end

    -- FYI must call before building extmarks (if needed strips duplicate prefix)
    self:fim_fixes()
    if not self.has_prediction then
        if self.has_accepts then
            -- quick hack to make sure we don't go back to showing reasoning after full accept
            --  TODO fix this to not be so hacky (name wise)
            --     TODO differentiate when fully accepted and just reset at that point!
            return
        end
        if self.started_content then
            -- content was shown already; don't regress back to reasoning when
            -- a streaming fence-strip momentarily empties the prediction
            return
        end
        if not self.has_reasoning then
            return
        end
        -- * thinking dots
        self.first_line = dots:get_still_thinking_message(self.start_time)

        -- show reasoning (kinda fun to see! slower models this might make it palatable)
        -- maybe a runtime toggle so if I crank up level of thinking in gptoss (or use slower or verbose thinker model)
        -- then in that case I see thinking?
        --  heck maybe model specific + reasoning level (i.e. gptoss off/low do not show, medium/high show)? glm4.7/qwen3.6 show
        local reasoning = self:get_reasoning()
        -- FYI concat every time is TERRIBLY inefficient, just concat on each token or whenever you want to show part of it
        --  but O(n) over concat which is O(n) too is O(n^2) and terrible lol
        self.rest_of_lines = split_lines(reasoning)

        -- Build reasoning virtual lines with different highlight group
        local reasoning_virt_lines = {}
        for i, line in ipairs(self.rest_of_lines) do
            table.insert(reasoning_virt_lines, { { line, HLGroups.PREDICTION_REASONING } })
        end

        -- Set reasoning extmarks with different highlight
        vim.api.nvim_buf_set_extmark(self.bufnr, extmarks_ns_id, cursor.line_base0, cursor.col_base0, -- 0-indexed
            {
                virt_text = { { self.first_line, HLGroups.PREDICTION_THINKING } },
                virt_lines = reasoning_virt_lines,
                virt_text_pos = "inline",
            })
        return
    end

    -- * highlight cursor line prefix overlap with red bg
    if self.has_duplicate_prefix then
        self.extmarks.dup_highlight = vim.api.nvim_buf_set_extmark(
            self.bufnr,
            extmarks_ns_id,
            cursor.line_base0,
            -- TODO if we only match part of prefix... we shouldn't highlight all of it! rare but still support this?
            0, -- start from beginning of line
            {
                end_line = cursor.line_base0,
                end_col = cursor.col_base0,
                hl_group = HLGroups.PREDICTION_DUPLICATE_PREFIX,
                hl_eol = false,
            }
        )
    end

    local virt_lines = {}
    for i, line in ipairs(self.rest_of_lines) do
        table.insert(virt_lines, { { line, HLGroups.PREDICTION_TEXT } })
    end

    -- * Draw the delta at its insertion position (falls back to the cursor when
    --   no aligned position is known, e.g. after a partial accept).
    local display_line_base0 = cursor.line_base0
    local display_col_base0 = cursor.col_base0
    if self.insertion_line_base0 ~= nil then
        display_line_base0 = self.insertion_line_base0
        display_col_base0 = self.insertion_col_base0 or 0
    end

    local first_line_virt_text = { { self.first_line, HLGroups.PREDICTION_TEXT } }
    vim.api.nvim_buf_set_extmark(self.bufnr, extmarks_ns_id, display_line_base0, display_col_base0, -- 0-indexed
        {
            virt_text = first_line_virt_text,
            virt_lines = virt_lines,
            virt_text_pos = "inline",
        })
end

function Prediction:clear_extmarks()
    vim.api.nvim_buf_clear_namespace(self.bufnr, extmarks_ns_id, 0, -1)

    -- Explicitly remove the duplicate prefix highlight if it exists
    if not self.extmarks then
        return
    end

    if self.extmarks.dup_highlight then
        pcall(vim.api.nvim_buf_del_extmark, self.bufnr, extmarks_ns_id, self.extmarks.dup_highlight)
        self.extmarks.dup_highlight = nil
    end

    if self.extmarks.failures then
        pcall(vim.api.nvim_buf_del_extmark, self.bufnr, extmarks_ns_id, self.extmarks.failures)
        self.extmarks.failures = nil
    end
end

function Prediction:mark_as_abandoned()
    self.abandoned = true
end

function Prediction:insert_accepted(insert_lines)
    self.skip_text_changed_from_accept_suggestion = true
    local controller = CursorController:new()

    -- * insert accepted text at the aligned position (fall back to cursor when
    --   no position is known, e.g. after a partial accept).
    local insert_line_base0 = self.insertion_line_base0
    local insert_col_base0 = self.insertion_col_base0
    if insert_line_base0 == nil then
        local cursor = controller:get_cursor_position()
        insert_line_base0 = cursor.line_base0
        insert_col_base0 = cursor.col_base0
    end

    -- INSERT b/c start == end == cursor position! (nothing to replace)
    vim.api.nvim_buf_set_text(
        self.bufnr, insert_line_base0, insert_col_base0,
        insert_line_base0, insert_col_base0, insert_lines)

    -- * move cursor
    local new_cursor = controller:calc_new_position(
        { line_base0 = insert_line_base0, col_base0 = insert_col_base0 },
        insert_lines)
    vim.api.nvim_win_set_cursor(controller.window_id, { new_cursor.line_base1, new_cursor.col_base0 }) -- (1,0)-indexed

    -- after accepting, subsequent accepts insert at the (moved) cursor
    self.insertion_line_base0 = nil
    self.insertion_col_base0 = nil
end

local BLANK_LINE = ""
function Prediction:accept_first_line()
    -- FYI instead of splitting every time... could make a class that buffers into line splits for me! use a table of chunks until hit \n... flush to the next line and start accumulating next line, etc
    if not self.has_prediction then
        return
    end

    -- PRN add integration testing of these buffer/cursor interactions

    -- * insert first line
    local first_line = self.first_line
    local insert_lines = { first_line }
    if #self.rest_of_lines > 0 then
        -- only wrap a line if there are more lines to accept!
        insert_lines = { first_line, BLANK_LINE }

        -- BTW the blank line is important...
        -- - w/o it, you end up eating one line below per accepted line...
        --   b/c new code is INSERTED into existing (cursor) line
        -- - so the new blank just adds the next line to insert into (one at a time)
    end

    self:insert_accepted(insert_lines)

    -- * update prediction
    self.prediction = table.concat(self.rest_of_lines, "\n")
    self.has_accepts = true
    self:fix_fim_and_redraw_extmarks()
end

function Prediction:accept_first_word()
    if not self.has_prediction then
        return
    end

    -- PRN add integration testing of these buffer/cursor interactions

    local first_line = self.first_line
    local _, word_end = first_line:find("[_%w]+") -- find first word (range)
    -- log:warn("  word_end", vim.inspect(word_end))
    local insert_lines = {}

    local one_non_word_remains = word_end == nil
    local one_word_remains = word_end == #first_line -- word_end == # chars in line ==> full match!
    local accepts_rest_of_line = one_non_word_remains or one_word_remains
    if accepts_rest_of_line then
        -- log:warn("  one_non_word_remains", vim.inspect(one_non_word_remains))
        -- log:warn("  one_word_remains", vim.inspect(one_word_remains))

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
        local first_word = first_line
        first_line = ""

        local last_predicted_line = #self.rest_of_lines == 0
        if last_predicted_line then
            insert_lines = { first_word }
        else
            insert_lines = { first_word, BLANK_LINE }
        end
    else
        -- take next word only (not end of line)
        local first_word = first_line:sub(1, word_end)
        first_line = first_line:sub(word_end + 1)

        insert_lines = { first_word }
    end
    -- log:warn("  insert_lines", vim.inspect(insert_lines))

    self:insert_accepted(insert_lines)

    -- * update prediction
    self.prediction = first_line .. "\n" .. table.concat(self.rest_of_lines, "\n")
    self.has_accepts = true
    -- FYI I don't need to update the cached values for first_line/rest_of_lines b/c they'll be recomputed in fix_fim_and_redraw_extmarks
    self:fix_fim_and_redraw_extmarks()
end

function Prediction:accept_all()
    if not self.has_prediction then
        return
    end

    local all_lines = { self.first_line, unpack(self.rest_of_lines) }
    self:insert_accepted(all_lines)

    -- FYI KEY TEST SCENARIO: complete to end of generated text
    --   * easy b/c no partial accept... whatever the model generates, insert it
    --   MOVE cursor to end of inserted text:
    --   - same line as last char
    --   - no extra blank lines

    -- * clear prediction
    self.prediction = "" -- strip all lines from the prediction (and update it)
    self.has_accepts = true
    self:fix_fim_and_redraw_extmarks()

    -- TODO SIGNAL next prediction when accept all? (and then consider this for other accept types if they are accepting remainder of prediction too (finishing accepting current prediction)
    --   frontend.ask_for_prediction({ bufnr = self.bufnr })
    --   FYI can also use Alt+Tab to do this, if I don't want it to be automatic... which is possible I won't like the aggressiveness of back to back predict=>acccept=>predict=>accept...
end

return Prediction
