local uv = vim.uv
local M = {}
local Prediction = require("ask-openai.prediction.prediction")
local legacy_completions = require("ask-openai.prediction.backends.legacy-completions")

-- FYI would need current prediction PER buffer in the future if want multiple buffers to have predictions at same time (not sure I want this feature)
M.current_prediction = nil -- set on module for now, just so I can inspect it easily

-- FYI useful to observe what is happening under hood, run in pane below nvim (don't need to esc and look at :messages)
--    tail -f /Users/wesdemos/.local/share/nvim/ask/ask-predictions.log
local log = require("ask-openai.prediction.logger").predictions()

function M.ask_for_prediction()
    M.stop_current_prediction()


    local original_row_1based, original_col = unpack(vim.api.nvim_win_get_cursor(0)) -- (1,0) based #s... aka original_row starts at 1, original_col starts at 0
    local original_row = original_row_1based - 1 -- 0-based now
    -- 100 did not work well here.. with 7b model too 30+ seconds to generate a response! 10 lines works very fast (faster than supermaven) and gives decent responses
    --   PRN race using FIM vs AR (complete) and show first completed suggestion and allow toggle to next?
    -- ... Zed uses 32 (max 64 totallines, 32 before/after by default) => shifted if near top/bottom of doc too
    -- PRN consider (when available) to get the lines back to a meaningful branch in the syntax tree of the code you are editing? does that help?
    local allow_lines = 80
    local first_row = original_row - allow_lines -- lets try to take entire document if avail! (in future clip at some key boundary... unsure how that would work best w/ how models are trained on FIM
    local last_row = original_row + allow_lines -- limit how much we consider past this point? or take it all too?

    -- adjust range so that we maximize context? is this good or not?
    -- FYI I am not sure I like this here... more lines after doesn't likely help much, more lines before may help

    local num_rows_total = vim.api.nvim_buf_line_count(0)
    if first_row < 0 then
        -- TODO write tests of this if I keep it
        last_row = last_row - first_row
        first_row = 0
    elseif last_row >= num_rows_total then
        local past = last_row - num_rows_total + 1
        last_row = num_rows_total - 1
        first_row = first_row - past
        -- todo do I have to ensure > 0 ? for first_row
    end
    -- log:trace("first_row", first_row, "last_row", last_row)

    -- TODO! pass clipboard too! doesn't even have to be used verbatim... can just bias context!

    local IGNORE_BOUNDARIES = false
    local current_line = vim.api.nvim_buf_get_lines(0, original_row, original_row + 1, IGNORE_BOUNDARIES)[1] -- 0based indexing
    local current_before_cursor = current_line:sub(1, original_col + 1) -- TODO include current cursor slot as before or after?
    local current_after_cursor = current_line:sub(original_col + 2)
    local context_before = vim.api.nvim_buf_get_lines(0, first_row, original_row, IGNORE_BOUNDARIES) -- 0based indexing
    local context_before_text = table.concat(context_before, "\n") .. current_before_cursor
    -- give some instructions in a comment (TODO use comment string to do this)

    local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")
    if vim.o.commentstring ~= nil then
        local comment_header = string.format(vim.o.commentstring, "the following code is from a file named: '" .. filename .. "'") .. "\n\n"
        context_before_text = comment_header .. context_before_text
        log:trace("comment_header: ", comment_header)
    else
        -- log:warn
    end

    local context_after = vim.api.nvim_buf_get_lines(0, original_row, last_row, IGNORE_BOUNDARIES) -- 0based indexing
    local context_after_text = current_after_cursor .. table.concat(context_after, "\n") -- IIAC \n is the line separator?

    -- PSM format:
    local prefix = context_before_text
    local suffix = context_after_text
    -- "middle" is what is generated
    local options = legacy_completions.build_request(prefix, suffix)

    -- log:trace("curl", table.concat(options.args, " "))

    local this_prediction = Prediction:new()
    M.current_prediction = this_prediction

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    options.on_exit = function(code, signal) -- uv.spawn
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
        -- log:trace("on_stdout chunk: ", data)
        if err then
            log:warn("on_stdout error: ", err)
            this_prediction:mark_generation_failed()
            return
        end
        if data then
            vim.schedule(function()
                local chunk, generation_done = legacy_completions.process_sse(data)
                if chunk then
                    this_prediction:add_chunk_to_prediction(chunk)
                end
                if generation_done then
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

function M.stop_current_prediction()
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

local rx = require("rx")
local TimeoutScheduler = require("ask-openai.rx.scheduler")
local scheduler = TimeoutScheduler.create()
local keypresses = rx.Subject.create()
local subkp = keypresses:subscribe(function()
    -- immediately clear/hide prediction, else slides as you type
    vim.schedule(function()
        M.stop_current_prediction()
    end)
end)
local debounced = keypresses:debounce(250, scheduler)
local sub = debounced:subscribe(function()
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
    M.stop_current_prediction()
end

function M.entering_insert_mode()
    log:trace("function M.entering_insert_mode()")
    M.cursor_moved_in_insert_mode()
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
    M.stop_current_prediction()
end

return M
