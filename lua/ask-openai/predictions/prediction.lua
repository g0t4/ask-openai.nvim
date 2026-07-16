local dots = require("ask-openai.frontends.thinking.dots")
local HLGroups = require("ask-openai.hlgroups")
local log = require("devtools.logs.logger").universal()
local CursorController = require "ask-openai.predictions.cursor_controller"

---@class Prediction
---@field id integer
---@field buffer integer
---@field prediction_cache { completion: string, cursor_prefix: string, first_line: string, rest_of_lines: string[], has_duplicate_prefix: boolean }
---@field extmarks table
---@field abandoned boolean         # user aborted prediction
---@field disable_cursor_moved boolean
---
---@field has_reasoning boolean
---@field private reasoning_chunks string[]
---
---@field start_time number
---@field fim_request? CurlRequest
---
---@field apply_template_only boolean -- true means send FIM to /apply-template endpoint (not real FIM) and just log the prompt (saves me from running --verbose-prompt with llama-server which is heavy for all requests and not easily toggled)
---
local Prediction = {}
local instance_metatable = { __index = Prediction }
local extmarks_ns_id = vim.api.nvim_create_namespace("ask-universal")

---@alias PredictionParameters { apply_template_only: boolean, }

---@param params? PredictionParameters
---@return Prediction
function Prediction.new(params)
    local self = {} -- FYI after changing to self being a new instance per prediction... instead of all using Prediction singleton... I might have issues w/ cancel/abort/back2back predictions as I type... just keep that in mind

    -- id was originaly intended to track current prediction and not let past predictions write to extmarks (for example)
    self.id = vim.uv.hrtime() -- might not need id if I can use object reference instead, we will see (id is helpful if I need to roundtrip identity outside lua process)
    -- (nanosecond) time based s/b sufficient, esp b/c there should only ever be one prediction at a time.. even if multiple in short time (b/c of keystrokes, there is gonna be 1ms or so between them at most)

    -- FYI AFAICT no timing benefits from using a StringBuffer vs string.__concat... just b/c of my requirement to have full string on every iteration
    -- see test code: lua/ask-openai/prediction/tests/benchmark/str_concat_vs_buffer.lua

    self.buffer = 0 -- 0 == current buffer
    self.extmarks = {}
    self.abandoned = false
    self.disable_cursor_moved = false
    self.has_reasoning = false
    self.reasoning_chunks = {}
    self.start_time = os.time()
    self.prediction_cache = {
        completion = "",
        cursor_prefix = nil, -- make explicit
    }

    params = params or {}
    self.apply_template_only = params.apply_template_only


    setmetatable(self, instance_metatable)
    return self
end

function Prediction:add_chunk_to_prediction(chunk, reasoning_content)
    if chunk then
        self.prediction_cache.completion = self.prediction_cache.completion .. chunk
        -- TODO check for cursor_prefix duplication and update cached fields so I can use that in redraw_extmarks without recalculating this ever extmark/chunk update
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
    return self.prediction_cache.completion and self.prediction_cache.completion ~= ""
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

---@return boolean failure -- if there's no content yet, then bail on redraw -- TODO remove this hack when I don't need it anymore
function Prediction:fim_fixes()
    -- * get cursor prefix one time
    if self.prediction_cache.cursor_prefix == nil then
        local controller = CursorController:new()
        local cursor = controller:get_cursor_position()
        local cursor_line_text = vim.api.nvim_buf_get_lines(self.buffer, cursor.line_base0, cursor.line_base0 + 1, false)[1] or ""
        local prefix = cursor_line_text:sub(1, cursor.col_base0)
        self.prediction_cache.cursor_prefix = prefix
    end
    -- * Check if prediction's first line starts with the cursor prefix (FIM duplication)
    -- TODO dedupe completion and use downstream for accepts and display
    --  TODO that way I don't need logic in accept/display to compute overlap in prefix (or suffix later)
    -- TODO suffix duplication? find traces first

    local cursor_prefix = self.prediction_cache.cursor_prefix
    local lines = split_lines(self.prediction_cache.completion)
    if #lines == 0 then
        if not self.has_reasoning then
            -- TODO? perhaps use a cached field too? and nuke return value which is weird
            return false
        end
        lines = { dots:get_still_thinking_message(self.start_time) }
    end

    local first_line = table.remove(lines, 1)
    local has_duplicate_prefix = cursor_prefix ~= ""
        and #first_line >= #cursor_prefix
        and first_line:sub(1, #cursor_prefix) == cursor_prefix
    -- TODO fields when done

    if has_duplicate_prefix then
        first_line = first_line:sub(#cursor_prefix + 1)
    end

    -- cache:
    self.prediction_cache.has_duplicate_prefix = has_duplicate_prefix
    self.prediction_cache.first_line = first_line
    self.prediction_cache.rest_of_lines = lines
    return true
end

function Prediction:redraw_extmarks()
    self:clear_extmarks()

    local controller = CursorController:new()
    local cursor = controller:get_cursor_position()

    if self.prediction_cache.completion == nil then
        print("unexpected... prediction is nil?")
        return
    end

    -- FYI must call before building extmarks (if needed strips duplicate prefix)
    if not self:fim_fixes() then
        -- TODO revisit this hack to return here too
        -- hack to bail if no chunks yet and no reasoning dots to show
        return
    end

    local first_line_virt_text
    if self.prediction_cache.has_duplicate_prefix then
        -- -- Add subtle annotation showing what was dropped
        local annotation = string.format("[%d spaces stripped]", #self.prediction_cache.cursor_prefix)
        first_line_virt_text = {
            { self.prediction_cache.first_line, HLGroups.PREDICTION_TEXT },
            { " " .. annotation .. " ",              HLGroups.STATS_CACHED }
        }

        -- Highlight the original duplicated characters in buffer with red bg
        self.extmarks.dup_highlight = vim.api.nvim_buf_set_extmark(
            self.buffer,
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
    else
        first_line_virt_text = { { self.prediction_cache.first_line, HLGroups.PREDICTION_TEXT } }
    end

    local virt_lines = {}
    for i, line in ipairs(self.prediction_cache.rest_of_lines) do
        table.insert(virt_lines, { { line, HLGroups.PREDICTION_TEXT } })
    end

    vim.api.nvim_buf_set_extmark(self.buffer, extmarks_ns_id, cursor.line_base0, cursor.col_base0, -- 0-indexed
        {
            virt_text = first_line_virt_text,
            virt_lines = virt_lines,
            virt_text_pos = "inline",
        })
end

function Prediction:clear_extmarks()
    vim.api.nvim_buf_clear_namespace(self.buffer, extmarks_ns_id, 0, -1)

    -- Explicitly remove the duplicate prefix highlight if it exists
    if self.extmarks and self.extmarks.dup_highlight then
        pcall(vim.api.nvim_buf_del_extmark, self.buffer, extmarks_ns_id, self.extmarks.dup_highlight)
        self.extmarks.dup_highlight = nil
    end
end

function Prediction:mark_as_abandoned()
    self.abandoned = true
end

function Prediction:insert_accepted(insert_lines)
    self.disable_cursor_moved = true
    local controller = CursorController:new()
    local cursor = controller:get_cursor_position()
    -- * FIX: Auto-strip repeated indentation prefix from FIM completion
    -- When models like gptoss120b repeat the cursor line's prefix (usually whitespace),
    -- we detect and strip it before insertion. This handles cases where the model
    -- outputs the full line instead of just the new code.
    local cursor_prefix = self.prediction_cache.cursor_prefix
    -- TODO use prediction_cache here

    if cursor_prefix ~= "" then
        local first_line = insert_lines[1]
        -- Check if first line starts with the same prefix (common case: indentation repetition)
        if #first_line >= #cursor_prefix and first_line:sub(1, #cursor_prefix) == cursor_prefix then
            log:info("🔧 FIM prefix auto-stripped:", {
                cursor_prefix = vim.inspect(cursor_prefix),
                original_first_line = vim.inspect(first_line),
                stripped_first_line = vim.inspect(first_line:sub(#cursor_prefix + 1)),
            })
            insert_lines[1] = first_line:sub(#cursor_prefix + 1)
        end
    end


    -- * insert accepted text
    -- INSERT b/c start == end == cursor position! (nothing to replace)
    vim.api.nvim_buf_set_text(self.buffer, cursor.line_base0, cursor.col_base0, cursor.line_base0, cursor.col_base0, insert_lines)

    -- * move cursor
    local new_cursor = controller:calc_new_position(cursor, insert_lines)
    vim.api.nvim_win_set_cursor(controller.window_id, { new_cursor.line_base1, new_cursor.col_base0 }) -- (1,0)-indexed
end

local BLANK_LINE = ""
function Prediction:accept_first_line()
    -- FYI instead of splitting every time... could make a class that buffers into line splits for me! use a table of chunks until hit \n... flush to the next line and start accumulating next line, etc
    local lines = split_lines(self.prediction_cache.completion)
    if #lines == 0 then
        return
    end

    -- PRN add integration testing of these buffer/cursor interactions

    -- * insert first line
    local first_line = table.remove(lines, 1)
    local insert_lines = { first_line }
    if #lines > 0 then
        -- only wrap a line if there are more lines to accept!
        insert_lines = { first_line, BLANK_LINE }

        -- BTW the blank line is important...
        -- - w/o it, you end up eating one line below per accepted line...
        --   b/c new code is INSERTED into existing (cursor) line
        -- - so the new blank just adds the next line to insert into (one at a time)
    end

    self:insert_accepted(insert_lines)

    -- * update prediction
    self.prediction_cache.completion = table.concat(lines, "\n")
    self.prediction_cache.cursor_prefix = nil -- force lookup
    self:redraw_extmarks()
end

function Prediction:accept_first_word()
    local lines = split_lines(self.prediction_cache.completion)
    if #lines == 0 then
        return
    end

    -- PRN add integration testing of these buffer/cursor interactions

    local _, word_end = lines[1]:find("[_%w]+") -- find first word (range)
    -- log:warn("  word_end", vim.inspect(word_end))
    local insert_lines = {}

    local one_non_word_remains = word_end == nil
    local one_word_remains = word_end == #lines[1] -- word_end == # chars in line ==> full match!
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
        local first_word = lines[1]
        lines[1] = ""

        local last_predicted_line = #lines == 1
        if last_predicted_line then
            insert_lines = { first_word }
        else
            insert_lines = { first_word, BLANK_LINE }
        end
    else
        -- take next word only (not end of line)
        local first_word = lines[1]:sub(1, word_end)
        lines[1] = lines[1]:sub(word_end + 1)

        insert_lines = { first_word }
    end
    -- log:warn("  lines[1]", vim.inspect(lines[1]))
    -- log:warn("  insert_lines", vim.inspect(insert_lines))

    self:insert_accepted(insert_lines)

    -- * update prediction
    self.prediction_cache.completion = table.concat(lines, "\n")
    self.prediction_cache.cursor_prefix = nil -- force lookup
    -- log:warn("  self.prediction_cache", vim.inspect(self.prediction_cache))
    self:redraw_extmarks()
end

function Prediction:accept_all()
    local lines = split_lines(self.prediction_cache.completion)
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
    self.prediction_cache.completion = "" -- strip all lines from the prediction (and update it)
    self.prediction_cache.cursor_prefix = nil -- force lookup
    self:redraw_extmarks()

    -- TODO SIGNAL next prediction when accept all? (and then consider this for other accept types if they are accepting remainder of prediction too (finishing accepting current prediction)
    --   frontend.ask_for_prediction()
    --   FYI can also use Alt+Tab to do this, if I don't want it to be automatic... which is possible I won't like the aggressiveness of back to back predict=>acccept=>predict=>accept...
end

function Prediction:IDEA_accept_line_with_replace_current_line()
    -- gptoss often recommends text that has full line (not just new text)... if I had accept line and replace existing line motion... that would make it far less painful!
    --
    -- alternative would be to do diffs and strip common parts... so I can show just the new text as if the model didn't screw up!
    -- - this would actually work as a basis for edit predictions (not just FIM) ... could start small with one line editing only
end

return Prediction
