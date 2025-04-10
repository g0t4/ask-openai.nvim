local uv = vim.uv
local M = {}
local Prediction = require("ask-openai.prediction.prediction")
local changes = require("ask-openai.prediction.context.changelists")

-- local backend = require("ask-openai.prediction.backends.legacy-completions")
local backend = require("ask-openai.prediction.backends.ollama")
-- local backend = require("ask-openai.prediction.backends.backendsvllm")

-- FYI would need current prediction PER buffer in the future if want multiple buffers to have predictions at same time (not sure I want this feature)
M.current_prediction = nil -- set on module for now, just so I can inspect it easily

-- FYI useful to observe what is happening under hood, run in pane below nvim (don't need to esc and look at :messages)
--    tail -f /Users/wesdemos/.local/share/nvim/ask/ask-predictions.log
local log = require("ask-openai.prediction.logger").predictions()


function M.get_line_range(current_row, allow_lines, total_lines_in_doc)
    -- FYI do not adjust for 0/1 based, assume all of these are in same 1/0 base
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

local IGNORE_BOUNDARIES = false
local CURRENT_BUFFER = 0

function M.ask_for_prediction()
    M.cancel_current_prediction()

    local original_row_1based, original_col = unpack(vim.api.nvim_win_get_cursor(CURRENT_BUFFER)) -- (1,0) based #s... aka original_row starts at 1, original_col starts at 0
    local original_row = original_row_1based - 1 -- 0-based now

    local allow_lines = 80
    local num_rows_total = vim.api.nvim_buf_line_count(CURRENT_BUFFER)
    -- TODO test for 0based vs 1based indexing in get_line_range (I know you can get a number past end of document but that works out given get_lines is END-EXCLUSIVE
    local first_row, last_row = M.get_line_range(original_row, allow_lines, num_rows_total)
    log:trace("first_row", first_row, "last_row", last_row, "original_row", original_row, "original_col", original_col)


    local current_line = vim.api.nvim_buf_get_lines(CURRENT_BUFFER, original_row, original_row + 1, IGNORE_BOUNDARIES)[1]
    -- get_lines is END-EXCLUSIVE, 0-based
    log:trace("current_line", current_line)

    local before_is_thru_col = original_col -- original_col is 0-based, but don't +1 b/c that would include the char under the cursor which goes after any typed/inserted chars
    -- test edge case: enter insert mode 'i' => type/paste char(s) => observe char under cursor position shifts right
    local current_line_before_split = current_line:sub(1, before_is_thru_col) -- sub is END-INCLUSIVE ("foobar"):sub(2,3) == "ob"
    log:trace("current_line_before (1 => " .. before_is_thru_col .. "): '" .. current_line_before_split .. "'")

    -- PRN revisit prediction when cursor has existing text "after" it
    -- - test case: remove text from a finished line of code (i.e. delete a param in a function call)
    --   => enter insert mode and qwen2.5-coder (BASE) does a stellar job completing that (respects EOS much better than instruct finetunes)
    -- - prediction can visually replace existing code (easiest and most logical given the existing text can be rewritten too).. inherently a diff based situation (assume model can rewrite remainder of line?)
    -- - actually, what appears to work is when it can just insert new text at the cursor
    -- - PRN what happens when it wants to insert more text after the existing text too or instead?
    --   - Actually, wait, this is the domain of a rewrite (not solely a prediction)
    --   - Prediction should only fill the domain of inserting text after/before existing text
    --   - If I want help w/ a line I can wipe the end to get all of it redone (that is not ideal for cases when the cue is midway or toward end but that is gonna have to wait for as AskImplicitRewrite :) that compliments AskExplicitRewrite

    local after_starts_at_char_under_cursor = original_col + 1 -- FYI original_col is 0 based, thus +1
    local current_line_after_split = current_line:sub(after_starts_at_char_under_cursor)
    log:trace("current_line_after (" .. after_starts_at_char_under_cursor .. " => end): '" .. current_line_after_split .. "'")

    local lines_before_current = vim.api.nvim_buf_get_lines(CURRENT_BUFFER, first_row, original_row, IGNORE_BOUNDARIES) -- 0based, END-EXCLUSIVE
    local document_prefix = table.concat(lines_before_current, "\n") .. "\n" .. current_line_before_split

    -- TODO edge cases for new line at end of current line? is that a concern
    local lines_after_current = vim.api.nvim_buf_get_lines(CURRENT_BUFFER, original_row + 1, last_row, IGNORE_BOUNDARIES) -- 0based END-EXCLUSIVE
    -- pass new lines verbatim so the model can understand line breaks (as well as indents) as-is!
    local document_suffix = current_line_after_split .. "\n" .. table.concat(lines_after_current, "\n")

    if log.is_verbose_enabled() then
        -- if in trace mode... combine document prefix and suffix and check if matches entire document:
        local entire_document = table.concat(vim.api.nvim_buf_get_lines(CURRENT_BUFFER, first_row, last_row, IGNORE_BOUNDARIES), "\n")
        local combined = document_prefix .. document_suffix
        if entire_document ~= combined then
            -- trace mode, check if matches (otherwise may be incomplete or not in expected format)
            log:error("document mismatch: prefix+suffix != entire document")
            log:trace("diff\n", vim.diff(entire_document, combined))
        end
    end



    -- *** add filename in a comment at start of file (prefix)
    -- local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(CURRENT_BUFFER), ":t")
    -- if vim.o.commentstring ~= nil then
    --     local comment_header = string.format(vim.o.commentstring, "the following code is from a file named: '" .. filename .. "'") .. "\n\n"
    --     document_prefix = comment_header .. document_prefix
    --     log:trace("comment_header: ", comment_header)
    -- else
    --     log:warn("vim.o.commentstring is nil, not including file name in comment header")
    -- end

    local recent_edits = changes.get_change_list_with_lines()
    -- local recent_edits = {}

    -- PSM format:
    local prefix = document_prefix
    local suffix = document_suffix
    -- "middle" is what is generated
    local options = backend.build_request(prefix, suffix, recent_edits)

    -- log:trace("curl", table.concat(options.args, " "))

    local this_prediction = Prediction:new()
    M.current_prediction = this_prediction

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    options.on_exit = function(code, signal)
        log:trace(string.format("spawn - exit code: %d  signal:%s", code, signal))
        if code ~= 0 then
            log:error("spawn - non-zero exit code:", code, "Signal:", signal)
        end
        stdout:close()
        stderr:close()
    end

    M.handle, M.pid = uv.spawn(options.command, {
        args = options.args,
        stdio = { nil, stdout, stderr },
    }, options.on_exit)

    options.on_stdout = function(err, data)
        log:trace("on_stdout chunk: ", data)
        if err then
            log:warn("on_stdout error: ", err)
            this_prediction:mark_generation_failed()
            return
        end
        if data then
            vim.schedule(function()
                local chunk, generation_done, done_reason = backend.process_sse(data)
                if chunk then
                    this_prediction:add_chunk_to_prediction(chunk)
                end
                if generation_done then
                    if not this_prediction:any_chunks() then
                        -- FYI great way to test this, go to a line that is done (i.e. a return) and go into insert mode before the returned variable and it almost always suggests that is EOS (at least with qwen2.5-coder + ollama)
                        log:trace("DONE, empty prediction, done reason: '" .. (done_reason or "") .. "'")
                    end
                    this_prediction:mark_generation_finished()
                end
            end)
        end
    end
    uv.read_start(stdout, options.on_stdout)

    options.on_stderr = function(err, data)
        log:warn("on_stderr chunk: ", data)
        if err then
            log:warn("on_stderr error: ", err)
        end
    end
    uv.read_start(stderr, options.on_stderr)
end

function M.cancel_current_prediction()
    local this_prediction = M.current_prediction
    if not this_prediction then
        return
    end
    M.current_prediction = nil
    this_prediction:mark_as_abandoned()

    vim.schedule(function()
        this_prediction:clear_extmarks()
    end)

    local handle = M.handle
    local pid = M.pid
    M.handle = nil
    M.pid = nil
    if handle ~= nil and not handle:is_closing() then
        log:trace("Terminating process, pid: ", pid)

        handle:kill("sigterm")
        handle:close()
        -- FYI ollama should show that connection closed/aborted
    end
end

local ignore_filetypes = {
    "TelescopePrompt",
    "NvimTree",
    "DressingInput", -- pickers from nui (IIRC) => in nvim tree add a file => the file name box is one of these
    -- TODO make sure only check this on enter buffer first time? not on every event (cursormoved,etc)
}

local ignore_buftypes = {
    "nofile", -- rename refactor popup window uses this w/o a filetype, also Dressing rename in nvimtree uses nofile
    "terminal",
}
local keys = require("ask-openai.prediction.keys")
local keypresses, debounced = keys.create_keypresses_observables()
local keypresses_subscription = keypresses:subscribe(function()
    -- immediately clear/hide prediction, else slides as you type
    vim.schedule(function()
        M.cancel_current_prediction()
    end)
end)
local debounced_subscription = debounced:subscribe(function()
    vim.schedule(function()
        log:trace("CursorMovedI debounced")

        if vim.fn.mode() ~= "i" then
            return
        end

        M.ask_for_prediction()
    end)
end)

function M.cursor_moved_in_insert_mode()
    if M.current_prediction ~= nil and M.current_prediction.disable_cursor_moved == true then
        log:trace("Disabled CursorMovedI, skipping...")
        M.current_prediction.disable_cursor_moved = false -- just skip one time
        -- basically this is called after accepting/inserting the new content (AFAICT only one time too)
        return
    end

    if vim.tbl_contains(ignore_buftypes, vim.bo.buftype)
        or vim.tbl_contains(ignore_filetypes, vim.bo.filetype) then
        return
    end

    keypresses:onNext({})
end

function M.leaving_insert_mode()
    M.cancel_current_prediction()
end

function M.entering_insert_mode()
    log:trace("function M.entering_insert_mode()")
    M.cursor_moved_in_insert_mode()
end

function M.pause_stream_invoked()
    if not M.current_prediction then
        return
    end
    M.current_prediction:pause_new_chunks()
end

function M.resume_stream_invoked()
    if not M.current_prediction then
        return
    end
    M.current_prediction:resume_new_chunks()
end

function M.accept_all_invoked()
    log:trace("Accepting all predictions...")
    if not M.current_prediction then
        return
    end
    M.current_prediction:accept_all()
end

function M.accept_line_invoked()
    log:trace("Accepting line prediction...")
    if not M.current_prediction then
        return
    end
    M.current_prediction:accept_first_line()
end

function M.accept_word_invoked()
    log:trace("Accepting word prediction...")
    if not M.current_prediction then
        return
    end
    M.current_prediction:accept_first_word()
end

function M.vim_is_quitting()
    -- PRN detect rogue curl processes still running?
    log:trace("Vim is quitting, stopping current prediction (ensures curl is terminated)...")
    M.cancel_current_prediction()
end

return M
