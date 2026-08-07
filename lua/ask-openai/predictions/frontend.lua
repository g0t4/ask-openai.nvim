local uv = vim.uv
local Prediction = require("ask-openai.predictions.prediction")
local ansi = require("devtools.ansi")
local rag_client = require("ask-openai.rag.client")
local api = require("ask-openai.api")
local perf = require("ask-openai.perf")
local log = require("devtools.logs.logger").universal()
require("ask-openai.predictions.prefix_suffix")
local ps = require("ask-openai.predictions.prefix_suffix")
local lualine = require('ask-openai.status.lualine')
local stats = require("ask-openai.predictions.stats")
local Curl = require("ask-openai.backends.curl")
local CurlRequest = require("ask-openai.backends.curl_request")
local FimBackend = require("ask-openai.predictions.backends.fim_backend")
local llama_server_client = require("ask-openai.backends.llama_cpp.llama_server_client")
local config = require("ask-openai.config")
local buffer_state = require("ask-openai.predictions.buffer_state")
local ansi = require("devtools.ansi")

---@class PredictionsFrontend : StreamingFrontend
local PredictionsFrontend = {}

--- Get the current prediction for the active buffer.
--- @param bufnr integer
--- @return Prediction|nil
function PredictionsFrontend._get_current_prediction(bufnr)
    -- log:info("GET prediction", bufnr)
    if bufnr == nil or bufnr == 0 then
        error("bufnr must be non-zero in _get_current_prediction: " .. tostring(bufnr))
    end
    return buffer_state.buffer_state_for(bufnr).ask_openai_current_prediction
end

--- Set the current prediction for the active buffer.
--- @param prediction Prediction|nil
function PredictionsFrontend._set_current_prediction(bufnr, prediction)
    -- log:info("SET prediction", bufnr, prediction)
    -- log:info("SET prediction", bufnr)
    buffer_state.buffer_state_for(bufnr).ask_openai_current_prediction = prediction
end

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
local ignore_filetypes = {
    "TelescopePrompt",
    "TelescopeResults",
    "NvimTree",
    "DressingInput", -- pickers from nui (IIRC) => in nvim tree add a file => the file name box is one of these
}
---@param params? PredictionParameters
function PredictionsFrontend.ask_for_prediction(params)
    PredictionsFrontend.cancel_current_prediction(params.bufnr)

    -- * disable predictions in some windows
    --  TODO do I need this anymore? I swear I setup predictions to attach on BufEnter... and that already ignores specific filetypes (and other factors)?
    if vim.tbl_contains(ignore_buftypes, vim.bo.buftype)
        or vim.tbl_contains(ignore_filetypes, vim.bo.filetype) then
        -- -- but, allow renames:
        -- if not is_rename_window() then
        --     return
        -- end
        return
    end

    local this_prediction = Prediction.new(params)
    PredictionsFrontend._set_current_prediction(params.bufnr, this_prediction)

    local enable_rag = api.is_rag_enabled()
    local ps_chunk = ps.get_prefix_suffix_chunk()

    -- Register with performance registry for lualine display
    perf.register("fim", this_prediction.performance)

    ---@param rag_matches LSPRankedMatch[]
    local function then_send_fim(rag_matches)
        local fim_request = FimBackend:new(ps_chunk, rag_matches):fim_request()
        assert(fim_request.body ~= nil)

        if this_prediction.apply_template_only then
            -- PRN? move this out into its own module, composed with new open_float
            local response = llama_server_client.apply_template(fim_request.base_url, fim_request.body)
            local FloatWindow = require("ask-openai.helpers.float_window")
            local lines = vim.split(response.body.prompt, '\n')
            ---@type FloatWindowOptions
            local opts = { width_ratio = 0.8, height_ratio = 0.8, filetype = "harmony" }
            local buf, win = FloatWindow:new(opts, lines)
            -- PRN? setup harmony grammar for filetype + coloring with treesitter?
            -- PRN? or use LinesBuilder for lines w/ extmarks using LinesBuilder (not hard to do either, and would get me to setup a simple parser!)
            return
        end

        this_prediction.fim_request = fim_request

        --- Extracts the appropriate SSE parsing result based on the current FIM backend.
        ---@param sse_parsed table The raw SSE data to be parsed.
        ---@return table sse_result The parsed SSE result.
        local function _extract_sse_fields(sse_parsed)
            if fim_request.endpoint == CompletionsEndpoints.llamacpp_completions then
                return parse_sse_llamacpp_completions(sse_parsed)
            end
            if fim_request.endpoint == CompletionsEndpoints.v1_chat_completions then
                return parse_sse_v1_chat_completions(sse_parsed)
            end
            error("Unsupported FIM endpoint: " .. tostring(fim_request.endpoint))
        end

        ---@type OnParsedSSE
        local function on_parsed_data_sse(sse_parsed)
            this_prediction.performance:token_arrived()
            -- log:info("sse_parsed", sse_parsed)

            -- use defer_fn w/ 500ms to reproduce "stuck" predictions
            -- also found that toggling off the copilot while a prediction is visible, results in a stuck prediction
            vim.schedule(function()
                if this_prediction.abandoned then
                    -- DO NOT update prediction text if it's been abandoned!
                    -- reproduce bug by comment out this check...
                    -- then set 500ms delay using defer_fn
                    -- then trigger a prediction and cancel it midway and it'll be stuck!
                    log:trace(ansi.yellow_bold("skipping on_stdout chunk b/c prediction is abandoned, if you see many of these in a row... that likely means the request wasn't canceled!"))
                    return
                end

                local sse_fields = _extract_sse_fields(sse_parsed)

                if sse_fields.content or sse_fields.reasoning_content then
                    this_prediction:add_chunk_sse(sse_fields)
                end

                if sse_fields.done then
                    local logging_tokens = require("ask-openai.logs.tokens")

                    -- Build both reasoning and content outputs in a single pass
                    local outputs = logging_tokens.probability_colored_outputs(this_prediction.all_sses)

                    -- Log reasoning with probability coloring if available
                    if this_prediction.has_reasoning and outputs.reasoning ~= "" then
                        log:info(ansi.yellow_bold("REASONING:\n"), outputs.reasoning)
                    end
                    -- Log prediction with probability coloring if available
                    if outputs.content ~= "" then
                        log:info(ansi.cyan_bold("PREDICTION:\n"), outputs.content)
                    else
                        -- FYI great way to test this, go to a line that is done (i.e. a return) and go into insert mode before the returned variable and it almost always suggests that is EOS (at least with qwen2.5-coder)
                        log:trace(ansi.yellow_bold("DONE, empty prediction") .. ", done reason: '" .. (sse_fields.finish_reason or "") .. "'")

                        -- TODO real fix for empty response to remove thinking tokens:
                        -- good test case is to go b/w ends (below) and insert new line (empty) will likely result in a blank eventually (check reasoning too to confirm)
                        -- FYI might have a similar issue in other spots... maybe parlay this into a final cleanup step?
                        this_prediction:clear_extmarks()
                    end
                end
            end)
        end

        ---@type OnCurlExitedSuccessfully
        local function on_curl_exited_successfully()
            -- placeholder, not sure I will even need this
        end

        ---@type ExplainError
        local function explain_error(message)
            table.insert(this_prediction.failures, message)
            vim.schedule(function()
                this_prediction:fix_fim_and_redraw_extmarks()
                -- vim.notify(message, vim.log.levels.ERROR)
            end)
        end

        ---@type OnParsedSSE
        local function on_sse_llama_server_timings(sse)
            this_prediction.performance:overall_done()
            stats.show_prediction_stats(sse, this_prediction.performance)
        end

        local function get_flags()
            local flags = {}
            if this_prediction.has_duplicate_prefix then
                flags["fim_duplicate_prefix"] = this_prediction._trace_only_duplicate_prefix
            end
            return flags
        end

        ---@type StreamingFrontend
        local frontend = {
            on_parsed_data_sse = on_parsed_data_sse,
            on_curl_exited_successfully = on_curl_exited_successfully,
            explain_error = explain_error,
            on_sse_llama_server_timings = on_sse_llama_server_timings,
            -- FYI for now leave _wrapper in name for now to differentiate from actual function get_flags
            get_flags_wrapper = get_flags,
        }

        log:info("Curl.spawn(fim)")
        Curl.spawn(fim_request, frontend)
    end

    if enable_rag and rag_client.is_rag_supported_in_current_file() then
        if not vim.lsp.get_clients({ name = "ask_language_server", bufnr = 0 })[1] then
            -- FYI this check of client ready, must have immaterial overhead for working clients
            --  would be better to do no checks than slow down normal use
            log:error("ask_language_server not available, sending FIM w/o RAG")
            then_send_fim({})
            return
        end
        -- FYI vim.lsp.get_clients is taking ~3us for case when the LSP is operational, imperceptible overhead

        local this_request_ids, cancel -- declare in advance so closure can access
        this_prediction.performance:rag_started()

        ---@param obj SemanticGrepWithTimeoutResponseObj
        local function on_rag_response(obj)
            -- * make sure prior (canceled) rag request doesn't still respond
            -- if this prediction is no longer the current one for its buffer, a newer keystroke replaced it
            --  (or it was canceled), so these results are stale and must be skipped.
            --  object identity is sufficient here since each keystroke creates a fresh Prediction instance
            if PredictionsFrontend._get_current_prediction(this_prediction.bufnr) ~= this_prediction then
                log:warn("possibly stale rag results, skipping...")
                return
            end
            -- ** DO NOT LOOK AT A RESPONSE (neither isError nor matches) IF IT IS NOT FOR THE LATEST REQUEST!
            -- FYI DO NOT TOUCH this_prediction before checking that it is still most recent

            if obj.result.isError then
                local msg = "skipping RAG " .. vim.inspect(obj.result.error)
                table.insert(this_prediction.failures, msg)
                log:error("RAG failed in PredictionsFrontend, skipping RAG " .. vim.inspect(obj))
                this_prediction:fix_fim_and_redraw_extmarks()
                -- vim.notify(message)
            end

            -- TODO check this_request_ids before mark perf done! that's why we have double error!
            --  TODO in fact before check isError, like RewriteFrontend, skip if not last request for bufnr

            -- FYI unroll all rag specific safeguards here so that logic doesn't live inside send_fim
            log:info("this_prediction.id", this_prediction.id)
            this_prediction.performance:rag_done()

            if this_prediction.rag_cancel == nil then
                log:error("rag appears canceled, skipping on_rag_response...")
                return
            end

            -- clear cancel so not getting cancel message after retrieval (on next keystroke)
            this_prediction.rag_cancel = nil
            this_prediction.rag_request_ids = nil

            then_send_fim(obj.result.matches or {})
        end

        this_prediction.rag_cancel = function()
            log:warn("canceling RAG")
            this_prediction.rag_cancel = nil
            cancel()
            this_prediction.rag_request_ids = nil
        end

        ---@param str string
        ---@return string
        local function trim(str)
            return (str:gsub("^%s*(.-)%s*$", "%1"))
        end

        ---@param ps_chunk PrefixSuffixChunk
        ---@returns string? -- FIM query string, or nil to disable FIM Semantic Grep
        local function fim_concat(ps_chunk)
            -- FYI see fim_query_notes.md for past and future ideas for Semantic Grep selection w.r.t. RAG+FIM

            -- * TESTING FIM+RAG with cursor line ONLY for query
            local query = ps_chunk.cursor_line.before_cursor

            -- TODO add last user message custom instructions based on cursor_line situation for FIM...
            --     in middle of line => suggest intra line completion, rarely multiline
            --     at end of line => suggest finish current line and/or multiline
            --     blank line => suggest multiline

            if trim(query) == "" then
                local few_before_text = table.concat(ps_chunk.cursor_line.few_lines_before or {}, "\n") or ""
                if vim.trim(few_before_text) ~= "" then
                    query = few_before_text
                else
                    log:trace(ansi.white_bold(ansi.red_bg("SKIPPING RAG in FIM b/c cursor line is empty (before cursor) and nothing in a few lines above either")))
                    -- PRN allow suffix if empty prefix line? OR take a few lines around it?
                    -- PRN previous line? with a non-empty value? if so, pass all lines or a subset from ps_chunk builder (on ps_chunk)
                    return nil
                end
            end

            -- log:trace(string.format("fim_concat: query=%q", query))
            return query
        end

        local query = fim_concat(ps_chunk)
        if query == nil then
            -- no query == SKIP RAG (NOT A FAILURE)
            then_send_fim({})
            return
        end

        this_request_ids, cancel = rag_client.context_query_fim(query, on_rag_response)
        this_prediction.rag_request_ids = this_request_ids
    else
        this_prediction.rag_cancel = nil
        this_prediction.rag_request_ids = nil
        then_send_fim({})
    end
end

--- @param bufnr integer
function PredictionsFrontend.cancel_current_prediction(bufnr)
    -- PRN stdout/stderr:read_stop() to halt on_stdout/stderr callbacks from firing again (before handle:close())?!
    local this_prediction = PredictionsFrontend._get_current_prediction(bufnr)
    if not this_prediction then
        log:info("no prediction to cancel")
        return
    end
    if this_prediction.rag_cancel then
        this_prediction.rag_cancel()
    end
    PredictionsFrontend._set_current_prediction(bufnr, nil)
    this_prediction:mark_as_abandoned()

    vim.schedule(function()
        this_prediction:clear_extmarks()
    end)

    -- FYI both this_prediction and request are new with each keystroke
    CurlRequest.terminate(this_prediction.fim_request)
end

local debouncing = require("ask-openai.rx.debouncing")
local input_events, debounced_events = debouncing.create_typing_debounced_observable_by_bufnr()
local rx = require('rx')
local input_events = rx.Subject.create()
local input_events_subscription = input_events:subscribe(function(event)
    --- @cast event ObservableInputEvent
    log:info("input_event", event.bufnr)

    -- immediately clear/hide prediction, else slides as you type
    PredictionsFrontend.cancel_current_prediction(event.bufnr)
    -- end)
    -- local debounced_subscription = debounced_events:subscribe(function(event)
    --- @cast event ObservableInputEvent
    -- log:info("debounced prediction trigger", event.bufnr)

    -- use vim.schedule to ensure I can perform editor operations when debounced signal fires
    --  OR check if `vim.in_fast_event()` returns `false`?
    vim.schedule(function()
        PredictionsFrontend.start_predicting({ bufnr = event.bufnr })
    end)
end)

---@param params PredictionParameters
function PredictionsFrontend.start_predicting(params)
    if vim.fn.mode() ~= "i" then
        log:info("cannot predict outside insert mode")
        return
    end
    log:info("start predict")

    PredictionsFrontend.ask_for_prediction({ bufnr = params.bufnr })
end

function PredictionsFrontend.text_changed(bufnr)
    local current_prediction = PredictionsFrontend._get_current_prediction(bufnr)
    if current_prediction and current_prediction.skip_text_changed_from_accept_suggestion == true then
        -- FYI IIUC this is also important not to cancel on partial accept?
        --  w/o this we'd cancel after partial accept
        --  think of this as suspending the TextChangedI event, right?
        -- log:trace("skip_text_changed_from_accept_suggestion == true, skipping this text_changed...")
        current_prediction.skip_text_changed_from_accept_suggestion = false -- skip once
        -- called after accepting/inserting text (AFAICT only once per accept)
        return
    end

    input_events:onNext({ bufnr = bufnr })
end

---@param event vim.api.keyset.create_autocmd.callback_args
function PredictionsFrontend.leaving_insert_mode(event)
    log:info("leaving_insert_mode", event.buf)
    PredictionsFrontend.cancel_current_prediction(event.buf)
    -- PRN I could trigger a clear of the debounced signal? that said leaving insert mode means it won't run anyways
end

---@param event vim.api.keyset.create_autocmd.callback_args
function PredictionsFrontend.entering_insert_mode(event)
    -- FYI do NOT push an event into your debounce stream... else you will just wait then when you use o/O => results in a new line (TextChangedI) and triggers a prediction too
    --   so just go right to a prediction here
    --   -  if you use "i" then it will be the prediction that runs
    --   - if you use "o"/"O" then this one will be canceled (cheap) and a new one started
    --     PRN would be maybe nice to withhold a new prediction if there are subsquent commands pending or running so I don't waste any time (i.e. no pred until that new line added which becomes part of prediction)
    log:info("entering_insert_mode, bufnr: ", event.buf)
    PredictionsFrontend.ask_for_prediction({ bufnr = event.buf })
end

function PredictionsFrontend.accept_all_invoked()
    local bufnr = vim.fn.bufnr()
    log:info("accept_all_invoked", bufnr)
    local current_prediction = PredictionsFrontend._get_current_prediction(bufnr)
    if not current_prediction then
        return
    end
    current_prediction:accept_all()
end

function PredictionsFrontend.accept_line_invoked()
    local bufnr = vim.fn.bufnr()
    log:info("accept_line_invoked", bufnr)
    local current_prediction = PredictionsFrontend._get_current_prediction(bufnr)
    if not current_prediction then
        return
    end
    current_prediction:accept_first_line()
end

function PredictionsFrontend.accept_word_invoked(event)
    local bufnr = vim.fn.bufnr()
    log:info("accept_word_invoked", bufnr)
    local current_prediction = PredictionsFrontend._get_current_prediction(bufnr)
    if not current_prediction then
        return
    end
    current_prediction:accept_first_word()
end

function PredictionsFrontend.new_prediction_invoked()
    local bufnr = vim.fn.bufnr()
    log:info("new_prediction_invoked", bufnr)
    PredictionsFrontend.start_predicting({ bufnr = bufnr })
end

function PredictionsFrontend.vim_is_quitting(event)
    local bufnr = vim.fn.bufnr()
    -- TODO wire up, this is valuable if a long running FIM is left to keep going even after neovim shutsdown
    log:info("vim_is_quitting", bufnr)
    PredictionsFrontend.cancel_current_prediction(bufnr)
end

local are_predictions_running = false

local AUGROUP = "ask-openai.prediction"

local KEYMAP_ACCEPT_ALL = '<Tab>'
local KEYMAP_ACCEPT_LINE = '<C-right>'
local KEYMAP_ACCEPT_WORD = '<M-right>'
local KEYMAP_REDO_PREDICTION = '<M-Tab>'

function PredictionsFrontend.start_predictions()
    if are_predictions_running then
        return
    end

    -- hardcoded keymaps
    vim.api.nvim_set_keymap('i', KEYMAP_ACCEPT_ALL, "",
        { noremap = true, callback = PredictionsFrontend.accept_all_invoked })

    vim.api.nvim_set_keymap('i', KEYMAP_ACCEPT_LINE, "",
        { noremap = true, callback = PredictionsFrontend.accept_line_invoked })

    vim.api.nvim_set_keymap('i', KEYMAP_ACCEPT_WORD, "",
        { noremap = true, callback = PredictionsFrontend.accept_word_invoked })

    vim.api.nvim_set_keymap('i', KEYMAP_REDO_PREDICTION, "",
        { noremap = true, callback = PredictionsFrontend.new_prediction_invoked })

    -- vim.keymap.set("n", "<leader>~", "<cmd>AskDumpEdits<CR>", {})

    function trigger_apply_template_dump()
        local bufnr = vim.fn.bufnr()
        log:info("trigger_apply_template_dump", bufnr)
        PredictionsFrontend.ask_for_prediction({
            bufnr = bufnr,
            apply_template_only = true,
        })
    end

    vim.keymap.set("n", "<leader>temp", trigger_apply_template_dump, {})

    -- event subscriptions
    vim.api.nvim_create_augroup(AUGROUP, { clear = true })
    vim.api.nvim_create_autocmd("InsertLeavePre", {
        group = AUGROUP,
        pattern = "*",
        callback = PredictionsFrontend.leaving_insert_mode
    })
    vim.api.nvim_create_autocmd("InsertEnter", {
        group = AUGROUP,
        pattern = "*",
        callback = PredictionsFrontend.entering_insert_mode
    })
    -- vim.api.nvim_create_autocmd("CursorMovedI", { -- FYI old event used to trigger prediction (replaced with TextChangedI below)
    vim.api.nvim_create_autocmd("TextChangedI", {
        -- FYI been using this for a LONG time now and no issues (AFAICT)
        group = AUGROUP,
        pattern = "*",
        callback = function(event)
            ---@cast event vim.api.keyset.create_autocmd.callback_args
            PredictionsFrontend.text_changed(event.buf)
        end
    })

    are_predictions_running = true
end

function PredictionsFrontend.stop_predictions()
    if not are_predictions_running then
        return
    end

    -- FYI pcall blocks error propagation (returns status code, though in this case I don't care about that)
    -- remove event triggers
    pcall(vim.api.nvim_del_augroup_by_name, AUGROUP) -- most del methods will throw if doesn't exist... so just ignore that

    -- remove keymaps (using same hardcoded values)
    pcall(vim.api.nvim_del_keymap, 'i', KEYMAP_ACCEPT_ALL)
    pcall(vim.api.nvim_del_keymap, 'i', KEYMAP_ACCEPT_LINE)
    pcall(vim.api.nvim_del_keymap, 'i', KEYMAP_ACCEPT_WORD)
    pcall(vim.api.nvim_del_keymap, 'i', KEYMAP_REDO_PREDICTION)

    are_predictions_running = false
end

function PredictionsFrontend.setup()
    if config.local_share.are_predictions_enabled() then
        PredictionsFrontend.start_predictions()
    end
end

return PredictionsFrontend
