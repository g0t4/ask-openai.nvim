local uv = vim.uv
local M = {}
local Prediction = require("ask-openai.prediction.prediction")
local ansi = require("ask-openai.prediction.ansi")
local rag_client = require("ask-openai.rag.client")
local api = require("ask-openai.api")
local FIMPerformance = require("ask-openai.prediction.fim_performance")
require("devtools.performance")
local log = require("ask-openai.logs.logger").predictions()
require("ask-openai.prediction.prefix_suffix")
local ps = require("ask-openai.prediction.prefix_suffix")
local lualine = require('ask-openai.status.lualine')

local OllamaFimBackend = require("ask-openai.prediction.backends.llama")
-- local backend = require("ask-openai.prediction.backends.backendsvllm")

-- FYI would need current prediction PER buffer in the future if want multiple buffers to have predictions at same time (not sure I want this feature)
M.current_prediction = nil -- set on module for now, just so I can inspect it easily

function M.ask_for_prediction()
    M.cancel_current_prediction()
    local enable_rag = api.is_rag_enabled()
    local ps_chunk = ps.get_prefix_suffix_chunk()
    local perf = FIMPerformance:new()

    ---@param rag_matches LSPRankedMatch[]
    function send_fim(rag_matches)
        local model = api.get_fim_model()
        local backend = OllamaFimBackend:new(ps_chunk, rag_matches, model)
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

                -- * timing
                if perf ~= nil then
                    perf:overall_done()
                    table.insert(messages, "\n")
                    if perf.rag_duration_ms ~= nil then
                        table.insert(messages, "RAG: " .. perf.rag_duration_ms .. " ms")
                    end
                    if perf.time_to_first_token_ms ~= nil then
                        table.insert(messages, "TTFT: " .. perf.time_to_first_token_ms .. " ms")
                    end
                    if perf:TTFT_minus_RAG_ms() ~= nil then
                        table.insert(messages, "  w/o RAG: " .. perf:TTFT_minus_RAG_ms() .. " ms")
                    end
                    if perf.total_duration_ms ~= nil then
                        table.insert(messages, "Total: " .. perf.total_duration_ms .. " ms")
                    end
                end

                local message = table.concat(messages, "\n")

                local notify = require("notify")
                if notify then
                    -- if using nvim-notify, then clear prior notifications
                    notify.dismiss({ pending = true, silent = true })
                end
                vim.notify(message, "info", { title = "FIM Stats" })
            end

            if data then
                perf:token_arrived()

                vim.schedule(function()
                    -- vim.defer_fn(function()
                    if this_prediction.abandoned then
                        -- DO NOT update prediction text if it's been abandoned!
                        -- reproduce bug by comment out this check...
                        -- then set 500ms delay using defer_fn
                        -- then trigger a prediction and cancel it midway and it'll be stuck!
                        log:info(ansi.yellow_bold("skipping on_stdout chunk b/c prediction is abandoned"))
                        return
                    end

                    local sse_result = backend.process_sse(data)
                    local chunk = sse_result.chunk
                    local generation_done = sse_result.done
                    local done_reason = sse_result.done_reason
                    if chunk or sse_result.reasoning_content then
                        this_prediction:add_chunk_to_prediction(chunk, sse_result.reasoning_content)
                    end
                    if generation_done then
                        if this_prediction.has_reasoning then
                            log:info("REASONING:\n", ansi.yellow(this_prediction:get_reasoning()))
                        end
                        if not this_prediction:any_chunks() then
                            -- FYI great way to test this, go to a line that is done (i.e. a return) and go into insert mode before the returned variable and it almost always suggests that is EOS (at least with qwen2.5-coder + ollama)
                            log:trace(ansi.yellow_bold("DONE, empty prediction") .. ", done reason: '" .. (done_reason or "") .. "'")

                            -- TODO real fix for empty response to remove thinking tokens:
                            -- good test case is to go b/w ends (below) and insert new line (empty) will likely result in a blank eventually (check reasoning too to confirm)
                            -- FYI might have a similar issue in other spots... maybe parlay this into a final cleanup step?
                            this_prediction:clear_extmarks()
                        end
                        this_prediction:mark_generation_finished()
                    end
                    if sse_result.stats then
                        lualine.set_last_fim_stats(sse_result.stats)
                        if api.are_notify_stats_enabled() then
                            show_stats(sse_result)
                        end
                    end
                end)
                -- end, 500) -- 500 ms makes it easy to reproduce "stuck" predictions
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
        if not vim.lsp.get_clients({ name = "ask_language_server", bufnr = 0 })[1] then
            -- FYI this check of client ready, must have immaterial overhead for working clients
            --  would be better to do no checks than slow down normal use
            log:error("RAG not available in current LSP, when it should be, so, sending FIM w/o RAG")
            send_fim({})
            return
        end
        -- FYI vim.lsp.get_clients is taking ~3us for case when the LSP is operational, imperceptible overhead

        local this_request_ids, cancel -- declare in advance so closure can access
        perf:rag_started()

        ---@param rag_matches LSPRankedMatch[]
        ---@param rag_failed boolean?
        function on_rag_response(rag_matches, rag_failed)
            -- FYI unroll all rag specific safeguards here so that logic doesn't live inside send_fim
            perf:rag_done()

            -- * make sure prior (canceled) rag request doesn't still respond
            if M.rag_request_ids ~= this_request_ids then
                -- I bet this is why sometimes I get completions that still fire even after cancel b/c the RAG results aren't actually stopped in time on server and so they come back
                --  and they arrive after next request started... the mismatch in request_ids will prevent that issue
                log:trace("possibly stale rag results, skipping: "
                    .. vim.inspect({ global_rag_request_ids = M.rag_request_ids, this_request_ids = this_request_ids }))
                return
            end

            if M.rag_cancel == nil then
                log:error("rag appears to have been canceled, skipping on_rag_response rag_matches results...")
                return
            end

            send_fim(rag_matches)
        end

        this_request_ids, cancel = rag_client.context_query_fim(ps_chunk, on_rag_response, function() send_fim({}) end)
        M.rag_cancel = cancel
        M.rag_request_ids = this_request_ids
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
