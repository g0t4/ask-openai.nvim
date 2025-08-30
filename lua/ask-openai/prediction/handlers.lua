local uv = vim.uv
local M = {}
local Prediction = require("ask-openai.prediction.prediction")
local ansi = require("ask-openai.prediction.ansi")
local rag_client = require("ask-openai.rag.client")
local api = require("ask-openai.api")

local OllamaFimBackend = require("ask-openai.prediction.backends.llama")
-- TODO rewrite other backends to use new builder pattern (not a big change):
--    TODO add :new, rearrange to self: methods
--    TODO only do this if and when I switch to another backend...
-- local backend = require("ask-openai.prediction.backends.backendsvllm")

-- FYI would need current prediction PER buffer in the future if want multiple buffers to have predictions at same time (not sure I want this feature)
M.current_prediction = nil -- set on module for now, just so I can inspect it easily

-- FYI useful to observe what is happening under hood, run in pane below nvim (don't need to esc and look at :messages)
--    tail -f /Users/wesdemos/.local/share/nvim/ask-openai/ask-predictions.log
local log = require("ask-openai.logs.logger").predictions()

function M.get_line_range(current_row, allow_lines, total_lines_in_doc)
    -- FYI do not adjust for 0/1-indexed, assume all of these are in same 0/1-index
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

local function get_prefix_suffix()
    -- TODO! add some tests here next time something goes wrong or needs changed
    local original_row_1indexed, original_col = unpack(vim.api.nvim_win_get_cursor(CURRENT_BUFFER)) -- (1,0)-indexed #s... aka original_row starts at 1, original_col starts at 0
    local original_row = original_row_1indexed - 1 -- 0-indexed now

    local allow_lines = 80
    local num_rows_total = vim.api.nvim_buf_line_count(CURRENT_BUFFER)
    -- TODO test for 0indexed vs 1indexed indexing in get_line_range (I know you can get a number past end of document but that works out given get_lines is END-EXCLUSIVE
    local first_row, last_row = M.get_line_range(original_row, allow_lines, num_rows_total)
    log:trace("first_row", first_row, "last_row", last_row, "original_row", original_row, "original_col", original_col)

    local current_line = vim.api.nvim_buf_get_lines(CURRENT_BUFFER, original_row, original_row + 1, IGNORE_BOUNDARIES)[1]
    -- get_lines is END-EXCLUSIVE, 0-indexed
    log:trace("current_line", current_line)

    local before_is_thru_col = original_col -- original_col is 0-indexed, but don't +1 b/c that would include the char under the cursor which goes after any typed/inserted chars
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

    -- TODO! add a PSM Buffer/Window Parser! and test it (like builder but on the parsing side)
    local after_starts_at_char_under_cursor = original_col + 1 -- FYI original_col is 0-indexed, thus +1
    local current_line_after_split = current_line:sub(after_starts_at_char_under_cursor)
    log:trace("current_line_after (" .. after_starts_at_char_under_cursor .. " => end): '" .. current_line_after_split .. "'")

    local lines_before_current = vim.api.nvim_buf_get_lines(CURRENT_BUFFER, first_row, original_row, IGNORE_BOUNDARIES) -- 0indexed, END-EXCLUSIVE
    local document_prefix = table.concat(lines_before_current, "\n") .. "\n" .. current_line_before_split

    -- TODO edge cases for new line at end of current line? is that a concern
    local lines_after_current = vim.api.nvim_buf_get_lines(CURRENT_BUFFER, original_row + 1, last_row, IGNORE_BOUNDARIES) -- 0indexed END-EXCLUSIVE
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
    return document_prefix, document_suffix
end


function M.ask_for_prediction()
    M.cancel_current_prediction()
    local enable_rag = api.is_rag_enabled()

    local document_prefix, document_suffix = get_prefix_suffix()

    ---@param rag_matches LSPRankedMatch[]
    function send_fim(rag_matches)
        -- use rag_matches ~= nil b/c hot mess of other calls here when rag not used -- TODO CLEANUP NONSENSE WES
        if enable_rag and rag_matches ~= nil and M.rag_cancel == nil then
            log:error("rag_cancel is nil, assuming RAG was canceled") -- should be rare, but possible
            return
        end
        -- TODO check response's request_ids vs last RAG request ids (avoid accepting past RAG matches)

        local backend = OllamaFimBackend:new(document_prefix, document_suffix, rag_matches)
        local spawn_curl_options = backend:request_options()

        -- log:trace("curl", table.concat(spawn_curl_options.args, " "))

        local this_prediction = Prediction:new()
        M.current_prediction = this_prediction

        local stdout = uv.new_pipe(false)
        local stderr = uv.new_pipe(false)
        assert(stdout ~= nil)
        assert(stderr ~= nil)

        spawn_curl_options.on_exit = function(code, signal)
            log:trace(string.format("spawn - exit code: %d  signal:%s", code, signal))
            if code ~= 0 then
                log:error("spawn - non-zero exit code:", code, "Signal:", signal)
            end
            stdout:close()
            stderr:close()
        end

        M.handle, M.pid = uv.spawn(spawn_curl_options.command,
            ---@diagnostic disable-next-line: missing-fields
            {
                args = spawn_curl_options.args,
                stdio = { nil, stdout, stderr },
            },
            spawn_curl_options.on_exit)

        spawn_curl_options.on_stdout = function(err, data)
            log:trace("on_stdout chunk: ", data)

            if err then
                log:warn("on_stdout error: ", err)
                this_prediction:mark_generation_failed()
                return
            end

            local function show_stats(sse_result)
                -- yes! this will help me remember to shut off debug logs when I don't need them!
                -- vim.notify("stats: gen_tps=" .. sse_result.stats.predicted_tokens_per_second)
                -- OR vim.print would probably be equally useful and somewhat annoying too
                -- TODO or extmarks in this mode?! or else branch with extmarks?
                local messages = {}
                table.insert(messages, "FIM Stats")
                local stats = sse_result.stats
                table.insert(messages, string.format("in: %d tokens @ %.2f tokens/sec", stats.prompt_tokens, stats.prompt_tokens_per_second))
                table.insert(messages, string.format("out: %d tokens @ %.2f tokens/sec", stats.predicted_tokens, stats.predicted_tokens_per_second))

                if stats.cached_tokens ~= nil then
                    table.insert(messages, string.format("cached: %d tokens", stats.cached_tokens))
                end

                if stats.draft_tokens ~= nil then
                    local pct = 0
                    if stats.draft_tokens > 0 then
                        pct = (stats.draft_tokens_accepted / stats.draft_tokens) * 100
                    end
                    table.insert(messages, string.format("draft: %d tokens, %d accepted (%.2f%%)", stats.draft_tokens, stats.draft_tokens_accepted, pct))
                end

                if stats.truncated_warning ~= nil then
                    table.insert(messages, string.format("truncated: %s", stats.truncated_warning))
                end


                -- lets report back some generation settings so I can see values used (defaults)
                local parsed_sse = stats.parsed_sse
                -- disable model for now, I forgot that llama-server echos back w/e you tell it... not what it is actually running!
                -- local model = parsed_sse.model
                -- if model then
                --     table.insert(messages, "model: " .. model)
                -- end

                if parsed_sse.generation_settings then
                    -- for now just go directly to generation settings, I am fine with that until I settle on what I want...
                    --  and actually, until I parse other backends for these values (if/when I get those setup)
                    local gen = parsed_sse.generation_settings
                    table.insert(messages, "") -- blank line to split out gen inputs
                    -- temperature
                    table.insert(messages, string.format("temperature: %.2f", gen.temperature))
                    -- top_p
                    table.insert(messages, string.format("top_p: %.2f", gen.top_p))
                    -- max_tokens
                    table.insert(messages, string.format("max_tokens: %d", gen.max_tokens))
                end

                local message = table.concat(messages, "\n")

                vim.notify(message)
            end

            if data then
                vim.schedule(function()
                    local sse_result = backend.process_sse(data)
                    local chunk = sse_result.chunk
                    local generation_done = sse_result.done
                    local done_reason = sse_result.done_reason
                    if chunk then
                        this_prediction:add_chunk_to_prediction(chunk)
                    end
                    if generation_done then
                        if not this_prediction:any_chunks() then
                            -- FYI great way to test this, go to a line that is done (i.e. a return) and go into insert mode before the returned variable and it almost always suggests that is EOS (at least with qwen2.5-coder + ollama)
                            log:trace(ansi.yellow_bold("DONE, empty prediction") .. ", done reason: '" .. (done_reason or "") .. "'")
                        end
                        this_prediction:mark_generation_finished()
                    end
                    if sse_result.stats then
                        if api.are_verbose_logs_enabled() then
                            show_stats(sse_result)
                        end
                    end
                end)
            end
        end
        uv.read_start(stdout, spawn_curl_options.on_stdout)

        spawn_curl_options.on_stderr = function(err, data)
            log:warn("on_stderr chunk: ", data)
            if err then
                log:warn("on_stderr error: ", err)
            end
        end
        uv.read_start(stderr, spawn_curl_options.on_stderr)
    end

    if enable_rag and rag_client.is_rag_supported_in_current_file() then
        local request_ids, cancel =
            rag_client.context_query_fim(document_prefix, document_suffix, send_fim)
        M.rag_cancel = cancel
        M.rag_request_ids = request_ids
        log:trace("RAG request ids: ", vim.inspect(request_ids))
        log:trace("RAG cancel: ", cancel)
    else
        send_fim({})
    end
end

function M.cancel_current_prediction()
    if M.rag_cancel then
        M.rag_cancel()
        M.rag_cancel = nil
    end
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
    "TelescopeResults",
    "NvimTree",
    "DressingInput", -- pickers from nui (IIRC) => in nvim tree add a file => the file name box is one of these
    -- TODO make sure only check this on enter buffer first time? not on every event (cursormoved,etc)
}
local function is_rename_window()
    if vim.bo.buftype ~= "nofile"
        or vim.bo.filetype ~= "DressingInput" then
        return false
    end
    local win_id = vim.api.nvim_get_current_win()
    local win_config = vim.api.nvim_win_get_config(win_id)
    -- messages.append(win_config)
    if not win_config then
        -- shouldn't happen AFAICT
        return false
    end

    -- win_config.title => { { " Rename to " } }
    is_rename = win_config.title[1][1] == " Rename to "
    -- TODO! ok now set smth somewhere to specify "detected file type" is "rename" for FILE rename... do I need to do any further filtering to determine that?
    --   ... vs say a variable rename?
    --   then, use that in FIM prompt builder to provide custom FIM instructions:
    --   - provide full path
    --   - provide file contents too? in a separate file_sep object?
    --   - ALSO yank context (might be stop gap to make this work the best w/o the above)
    return is_rename
end

local ignore_buftypes = {
    -- FYI with yank history and edits... rename window should be brought back b/c it will suggest good names for files
    --   should tell model specifically about the window that is open in this case (and maybe others)
    --   so it knows what task the user is performing
    --   put that into a file_sep section like WIP.md or smth?
    --
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
        -- this would be a good spot to expand and catch other file types too, rework is_rename_window to share get config
        if not is_rename_window() then
            return
        end
        -- allow renames to continue
    end

    keypresses:onNext({})
end

function M.leaving_insert_mode()
    M.cancel_current_prediction()
end

function M.entering_insert_mode()
    -- log:trace("function M.entering_insert_mode()")
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

function M.new_prediction_invoked()
    M.cursor_moved_in_insert_mode()
end

function M.vim_is_quitting()
    -- PRN detect rogue curl processes still running?
    log:trace("Vim is quitting, stopping current prediction (ensures curl is terminated)...")
    M.cancel_current_prediction()
end

return M
