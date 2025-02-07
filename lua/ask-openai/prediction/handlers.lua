local uv = vim.uv
local M = {}
local Prediction = require("ask-openai.prediction.prediction")
local changes = require("ask-openai.prediction.edits.changes") -- manually imported to be in scope for testing is all, nuke this later

-- local backend = require("ask-openai.prediction.backends.legacy-completions")
local backend = require("ask-openai.prediction.backends.api-generate")

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

function M.ask_for_prediction()
    M.cancel_current_prediction()

    local original_row_1based, original_col = unpack(vim.api.nvim_win_get_cursor(0)) -- (1,0) based #s... aka original_row starts at 1, original_col starts at 0
    local original_row = original_row_1based - 1 -- 0-based now

    local allow_lines = 80
    local num_rows_total = vim.api.nvim_buf_line_count(0)
    local first_row, last_row = M.get_line_range(original_row, allow_lines, num_rows_total)
    log:trace("first_row", first_row, "last_row", last_row, "original_row", original_row)

    local IGNORE_BOUNDARIES = false

    local current_line = vim.api.nvim_buf_get_lines(0, original_row, original_row + 1, IGNORE_BOUNDARIES)[1]
    -- get_lines is END-EXCLUSIVE, 0-based
    log:trace("current_line", current_line)

    local current_before_thru_cursor = current_line:sub(1, original_col + 1) -- sub is END-INCLUSIVE ("foobar"):sub(2,3) == "ob"
    -- TODO revisit what it means for there to be characters after the cursor... are we just generating for this one line then?
    --    mostly revieww how the completion is displayed
    local current_after_cursor = current_line:sub(original_col + 2)
    local context_before = vim.api.nvim_buf_get_lines(0, first_row, original_row, IGNORE_BOUNDARIES) -- 0based indexing
    local context_before_text = table.concat(context_before, "\n") .. current_before_thru_cursor

    local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")
    if vim.o.commentstring ~= nil then
        local comment_header = string.format(vim.o.commentstring, "the following code is from a file named: '" .. filename .. "'") .. "\n\n"
        context_before_text = comment_header .. context_before_text
        log:trace("comment_header: ", comment_header)
    else
        log:warn("vim.o.commentstring is nil, not including file name in comment header")
    end

    local context_after = vim.api.nvim_buf_get_lines(0, original_row, last_row, IGNORE_BOUNDARIES) -- 0based indexing
    -- TODO => confirm \n is the line separator:
    local context_after_text = current_after_cursor .. table.concat(context_after, "\n")

    -- local recent_edits = changes.get_change_list_with_lines()
    local recent_edits = {}

    -- PSM format:
    local prefix = context_before_text
    local suffix = context_after_text
    -- "middle" is what is generated
    local options = backend.build_request(prefix, suffix, recent_edits)

    -- log:trace("curl", table.concat(options.args, " "))

    local this_prediction = Prediction:new()
    M.current_prediction = this_prediction

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    options.on_exit = function(code, signal)
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
                local chunk, generation_done = backend.process_sse(data)
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
