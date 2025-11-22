local uv = vim.uv
local Prediction = require("ask-openai.predictions.prediction")
local ansi = require("ask-openai.predictions.ansi")
local rag_client = require("ask-openai.rag.client")
local api = require("ask-openai.api")
local FIMPerformance = require("ask-openai.predictions.fim_performance")
require("devtools.performance")
local log = require("ask-openai.logs.logger").predictions()
require("ask-openai.predictions.prefix_suffix")
local ps = require("ask-openai.predictions.prefix_suffix")
local lualine = require('ask-openai.status.lualine')
local stats = require("ask-openai.predictions.stats")
local Curl = require("ask-openai.backends.curl")
local LastRequest = require("ask-openai.backends.last_request")
local FimBackend = require("ask-openai.predictions.backends.fim_backend")

-- TODO! WIP - fully port this to be a StreamingFrontend!
--    FYI! I just added : StreamingFrontend below w/o implementing the interface

---@class PredictionsFrontend : StreamingFrontend
---@field handle? uv.uv_process_t
---@field pid? integer
local PredictionsFrontend = {}

PredictionsFrontend.current_prediction = nil

function PredictionsFrontend.ask_for_prediction()
    PredictionsFrontend.cancel_current_prediction()
    -- TODO create this_prediction here?
    local enable_rag = api.is_rag_enabled()
    local ps_chunk = ps.get_prefix_suffix_chunk()

    local perf = FIMPerformance:new()

    ---@param rag_matches LSPRankedMatch[]
    function send_fim(rag_matches)
        -- FYI! PoC is chat completions only => so gptoss (w/ thinking) for now is it (NOT qwen2.5coder)

        local model = api.get_fim_model()

        -- TODO rename to FimBodyBuilder? or FimRequestBuilder? or FimPromptBuilder?
        local backend = FimBackend:new(ps_chunk, rag_matches, model)
        local body = backend:body_for()
        assert(body ~= nil)

        -- TODO move this_prediction creation above? (before RAG too)
        local this_prediction = Prediction.new()
        PredictionsFrontend.current_prediction = this_prediction

        ---@type OnParsedSSE
        local function on_parsed_data_sse_with_choice(sse_parsed)
            -- if read_error then
            --     FYI bring this back later if it is needed, skip for now during PoC of Curl module
            --     this_prediction:mark_generation_failed()
            --     return
            -- end

            perf:token_arrived()

            -- use defer_fn w/ 500ms to reproduce "stuck" predictions
            -- also found that toggling off the copilot while a prediction is visible, results in a stuck prediction
            vim.schedule(function()
                if this_prediction.abandoned then
                    -- DO NOT update prediction text if it's been abandoned!
                    -- reproduce bug by comment out this check...
                    -- then set 500ms delay using defer_fn
                    -- then trigger a prediction and cancel it midway and it'll be stuck!
                    log:trace(ansi.yellow_bold("skipping on_stdout chunk b/c prediction is abandoned"))
                    return
                end

                -- TODO later support other servers format wise, see:
                --    lua/ask-openai/predictions/backends/fim_backend.lua:346-358
                --
                -- /completions on llama-server:
                --   local chunk, done, done_reason = parse_llama_cpp_server(sse_parsed) -- /completions non-openai
                --   -- TO DO => later => verify done here is correct (I set to stop field from /completions backend on llama cpp)
                --

                -- log:info("sse_parsed", vim.inspect(sse_parsed))
                local chunk, done, done_reason, reasoning_content
                if FimBackend.endpoint == CompletionsEndpoints.completions then
                    -- TODO test
                    chunk, done, done_reason = parse_llama_cpp_server(sse_parsed)
                elseif FimBackend.endpoint == CompletionsEndpoints.v1_chat then
                    -- FYI for PoC use /v1/chat/completions llama-server:
                    chunk, done, done_reason, reasoning_content = parse_sse_oai_chat_completions(sse_parsed) -- * WORKS!
                elseif FimBackend.endpoint == CompletionsEndpoints.ollama_api_chat then
                    -- TODO test
                    chunk, done, done_reason = parse_sse_ollama_api_chat(sse_parsed)
                else
                    -- TODO test
                    chunk, done, done_reason = parse_ollama_api_generate(sse_parsed)
                end

                if chunk or reasoning_content then
                    this_prediction:add_chunk_to_prediction(chunk, reasoning_content)
                end

                if done then
                    if this_prediction.has_reasoning then
                        -- log:info(ansi.yellow_bold("REASONING:\n"), ansi.yellow(this_prediction:get_reasoning()))
                    end
                    if this_prediction:any_chunks() then
                        -- log:info(ansi.cyan_bold("PREDICTION:\n"), ansi.cyan(this_prediction.prediction))
                    else
                        -- FYI great way to test this, go to a line that is done (i.e. a return) and go into insert mode before the returned variable and it almost always suggests that is EOS (at least with qwen2.5-coder + ollama)
                        log:trace(ansi.yellow_bold("DONE, empty prediction") .. ", done reason: '" .. (done_reason or "") .. "'")

                        -- TODO real fix for empty response to remove thinking tokens:
                        -- good test case is to go b/w ends (below) and insert new line (empty) will likely result in a blank eventually (check reasoning too to confirm)
                        -- FYI might have a similar issue in other spots... maybe parlay this into a final cleanup step?
                        this_prediction:clear_extmarks()
                    end
                    this_prediction:mark_generation_finished()
                end
            end)
        end

        ---@type OnCurlExitedSuccessfully
        local function on_curl_exited_successfully()
            -- placeholder, not sure I will even need this
        end

        ---@type ExplainError
        local function explain_error(text)
            -- TODO figure out this once PoC is working
            vim.notify("ERROR in new PREDICTIONS FRONTEND PoC: " .. text, vim.log.levels.ERROR)
        end

        ---@type OnParsedSSE
        local function on_sse_llama_server_timings(sse)
            stats.show_prediction_stats(sse, perf)
        end
        local frontend = {
            on_parsed_data_sse_with_choice = on_parsed_data_sse_with_choice,
            on_curl_exited_successfully = on_curl_exited_successfully,
            explain_error = explain_error,
            on_sse_llama_server_timings = on_sse_llama_server_timings,
        }

        log:info("hack.body", vim.inspect(body))
        log:info("hack.url", FimBackend.base_url)
        log:info("hack.endpoint", FimBackend.endpoint)

        local request = LastRequest:new({
            body = body,
            base_url = FimBackend.base_url,
            endpoint = FimBackend.endpoint,
            -- FYI FIRST test of this PoC is with /v1/chat/completions endpoint... later I can do others (i.e. non-thinking gptoss using /completions endpoint! or qwen2.5 coder that way too!)
            --    SO YOU will need to use gptoss too as qwen you only have setup IIRC to use manual prompt building /completions
        })

        Curl.spawn(request, frontend)
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
            if PredictionsFrontend.rag_request_ids ~= this_request_ids then
                -- I bet this is why sometimes I get completions that still fire even after cancel b/c the RAG results aren't actually stopped in time on server and so they come back
                --  and they arrive after next request started... the mismatch in request_ids will prevent that issue
                -- log:trace("possibly stale rag results, skipping: "
                --     .. vim.inspect({ global_rag_request_ids = M.rag_request_ids, this_request_ids = this_request_ids }))
                return
            end

            if PredictionsFrontend.rag_cancel == nil then
                -- log:error("rag appears to have been canceled, skipping on_rag_response rag_matches results...")
                return
            end

            send_fim(rag_matches)
        end

        this_request_ids, cancel = rag_client.context_query_fim(ps_chunk, on_rag_response, function() send_fim({}) end)
        PredictionsFrontend.rag_cancel = cancel
        PredictionsFrontend.rag_request_ids = this_request_ids
    else
        send_fim({})
    end
end

function PredictionsFrontend.cancel_current_prediction()
    -- PRN stdout/stderr:read_stop() to halt on_stdout/stderr callbacks from firing again (before handle:close())?!
    if PredictionsFrontend.rag_cancel then
        PredictionsFrontend.rag_cancel()
        PredictionsFrontend.rag_cancel = nil
    end
    local this_prediction = PredictionsFrontend.current_prediction
    if not this_prediction then
        return
    end
    PredictionsFrontend.current_prediction = nil
    this_prediction:mark_as_abandoned()

    vim.schedule(function()
        this_prediction:clear_extmarks()
    end)

    local handle = PredictionsFrontend.handle
    local pid = PredictionsFrontend.pid
    PredictionsFrontend.handle = nil
    PredictionsFrontend.pid = nil
    if handle ~= nil and not handle:is_closing() then
        -- log:trace("Terminating process, pid: ", pid)

        handle:kill("sigterm")
        handle:close()
    end
end

local ignore_filetypes = {
    "TelescopePrompt",
    "TelescopeResults",
    "NvimTree",
    "DressingInput", -- pickers from nui (IIRC) => in nvim tree add a file => the file name box is one of these
}
local function is_rename_window()
    -- TODO make sure only check this on enter buffer first time? not on every event (cursormoved,etc)
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
    -- TODO tell model about the window that is open (in some cases)...
    -- i.e. rename window (gather diff context too, i.e. what would help with renames?)
    return is_rename
end

local ignore_buftypes = {
    "nofile", -- rename refactor popup window uses this w/o a filetype, also Dressing rename in nvimtree uses nofile
    "terminal",
}
local keys = require("ask-openai.predictions.keys")
local keypresses, debounced = keys.create_keypresses_observables()
local keypresses_subscription = keypresses:subscribe(function()
    -- immediately clear/hide prediction, else slides as you type
    vim.schedule(function()
        PredictionsFrontend.cancel_current_prediction()
    end)
end)
local debounced_subscription = debounced:subscribe(function()
    vim.schedule(function()
        -- log:trace("CursorMovedI debounced")

        if vim.fn.mode() ~= "i" then
            return
        end

        PredictionsFrontend.ask_for_prediction()
    end)
end)

function PredictionsFrontend.cursor_moved_in_insert_mode()
    if PredictionsFrontend.current_prediction ~= nil and PredictionsFrontend.current_prediction.disable_cursor_moved == true then
        -- log:trace("Disabled CursorMovedI, skipping...")
        PredictionsFrontend.current_prediction.disable_cursor_moved = false -- skip once
        -- called after accepting/inserting text (AFAICT only once per accept)
        return
    end

    -- * disable predictions in some windows
    --  TODO do I need this anymore? I swear I setup predictions to attach on BufEnter... and that already ignores specific filetypes (and other factors)?
    if vim.tbl_contains(ignore_buftypes, vim.bo.buftype)
        or vim.tbl_contains(ignore_filetypes, vim.bo.filetype) then
        -- but, allow renames:
        if not is_rename_window() then
            return
        end
    end

    keypresses:onNext({})
end

function PredictionsFrontend.leaving_insert_mode()
    PredictionsFrontend.cancel_current_prediction()
end

function PredictionsFrontend.entering_insert_mode()
    PredictionsFrontend.cursor_moved_in_insert_mode()
end

function PredictionsFrontend.pause_stream_invoked()
    if not PredictionsFrontend.current_prediction then
        return
    end
    PredictionsFrontend.current_prediction:pause_new_chunks()
end

function PredictionsFrontend.resume_stream_invoked()
    if not PredictionsFrontend.current_prediction then
        return
    end
    PredictionsFrontend.current_prediction:resume_new_chunks()
end

function PredictionsFrontend.accept_all_invoked()
    if not PredictionsFrontend.current_prediction then
        return
    end
    PredictionsFrontend.current_prediction:accept_all()
end

function PredictionsFrontend.accept_line_invoked()
    if not PredictionsFrontend.current_prediction then
        return
    end
    PredictionsFrontend.current_prediction:accept_first_line()
end

function PredictionsFrontend.accept_word_invoked()
    if not PredictionsFrontend.current_prediction then
        return
    end
    PredictionsFrontend.current_prediction:accept_first_word()
end

function PredictionsFrontend.new_prediction_invoked()
    PredictionsFrontend.cursor_moved_in_insert_mode()
end

function PredictionsFrontend.vim_is_quitting()
    PredictionsFrontend.cancel_current_prediction()
end

return PredictionsFrontend
