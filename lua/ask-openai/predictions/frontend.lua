local uv = vim.uv
local Prediction = require("ask-openai.predictions.prediction")
local ansi = require("devtools.ansi")
local rag_client = require("ask-openai.rag.client")
local api = require("ask-openai.api")
local FIMPerformance = require("ask-openai.predictions.fim_performance")
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

--- Color text based on token probability.
--- Higher probability = less visible color (prob=1.0 has no color).
--- Lower probability = more intense red color.
---@param text string The text to color
---@param prob number|nil Token probability (0-1), nil means no coloring
---@return string Colored text with ANSI escape codes
local function color_by_probability(text, prob)
    -- No probability data available, return plain text
    if prob == nil then
        return text
    end

    -- Perfect confidence = no color
    if prob >= 1.0 then
        return text
    end

    -- Calculate intensity (0 = no color, 1 = full red)
    local intensity = 1.0 - prob
    -- Clamp to [0, 1]
    intensity = math.max(0, math.min(1, intensity))

    -- Color gradient: green (high confidence) -> yellow -> red (low confidence)
    -- At prob=1.0: no color (handled above)
    -- At prob=0.9-1.0: very subtle green tint
    -- At prob=0.7-0.9: yellow-green
    -- At prob=0.5-0.7: yellow-orange
    -- At prob<0.5: orange-red
    -- At prob~0.0: bright red

    local r, g, b
    if intensity < 0.33 then
        -- High confidence: green tint (low intensity)
        -- intensity 0-0.33 maps to rgb(200, 255, 200) -> rgb(255, 255, 0)
        local t = intensity / 0.33
        r = math.floor(200 + t * 55)
        g = 255
        b = math.floor(200 - t * 200)
    elseif intensity < 0.66 then
        -- Medium confidence: yellow to orange
        -- intensity 0.33-0.66 maps to rgb(255, 255, 0) -> rgb(255, 165, 0)
        local t = (intensity - 0.33) / 0.33
        r = 255
        g = math.floor(255 - t * 90)
        b = 0
    else
        -- Low confidence: orange to red
        -- intensity 0.66-1.0 maps to rgb(255, 165, 0) -> rgb(255, 0, 0)
        local t = (intensity - 0.66) / 0.34
        r = 255
        g = math.floor(165 * (1 - t))
        b = 0
    end
    return ansi.rgb(text, r, g, b)
end

--- Format a single token with its probability for logging.
---@param token string text
---@param prob number|nil Token probability (0-1)
---@return string Formatted string with probability indicator
local function format_token_with_prob(token, prob)
    local colored_text = color_by_probability(token, prob)
    -- Show probability in parentheses for tokens that aren't 100% confident
    if prob ~= nil and prob < 1.0 then
        return colored_text .. string.format(" (%.2f)", prob)
    end
    return colored_text
end

---@param sse_fields_list SseFieldsResult[]
---@return { reasoning: string, content: string }
local function build_probability_colored_outputs(sse_fields_list)
    local reasoning_parts = {}
    local content_parts = {}

    local sse_count = #sse_fields_list

    for sse_index_base0 = 0, sse_count - 1 do
        local sse_fields = sse_fields_list[sse_index_base0 + 1]

        local is_reasoning = sse_fields.reasoning_content and sse_fields.reasoning_content ~= ""
        if is_reasoning then
            table.insert(reasoning_parts, format_token_with_prob(sse_fields.reasoning_content, sse_fields.prob))
        end

        local is_content = sse_fields.content and sse_fields.content ~= ""
        if is_content then
            table.insert(content_parts, format_token_with_prob(sse_fields.content, sse_fields.prob))
        end
    end

    return {
        reasoning = table.concat(reasoning_parts),
        content = table.concat(content_parts),
    }
end

---@class PredictionsFrontend : StreamingFrontend
local PredictionsFrontend = {}

--- Get the current prediction for the active buffer.
--- @param bufnr integer
--- @return Prediction|nil
function PredictionsFrontend._get_current_prediction(bufnr)
    -- log:info("GET prediction", bufnr)
    if bufnr == nil or bufnr == 0 then
        error("bufnr must be non-zero in _get_current_prediction" .. tostring(bufnr))
    end
    return buffer_state.buffer_state_for(bufnr).ask_openai_current_prediction
end

--- Set the current prediction for the active buffer.
--- @param prediction Prediction|nil
function PredictionsFrontend._set_current_prediction(bufnr, prediction)
    -- log:info("SET prediction", bufnr, prediction)
    log:info("SET prediction", bufnr)
    buffer_state.buffer_state_for(bufnr).ask_openai_current_prediction = prediction
end

---@param params? PredictionParameters
function PredictionsFrontend.ask_for_prediction(params)
    PredictionsFrontend.cancel_current_prediction(params.bufnr)

    local this_prediction = Prediction.new(params)
    PredictionsFrontend._set_current_prediction(params.bufnr, this_prediction)

    local enable_rag = api.is_rag_enabled()
    local ps_chunk = ps.get_prefix_suffix_chunk()

    local performance = FIMPerformance:new()
    -- Register with performance registry for lualine display
    perf.register("fim", performance)

    ---@param rag_matches LSPRankedMatch[]
    function then_send_fim(rag_matches)
        -- TODO rename to FimBodyBuilder? or FimRequestBuilder? or FimPromptBuilder?
        local backend = FimBackend:new(ps_chunk, rag_matches)
        local body = backend:body_for()
        assert(body ~= nil)

        if this_prediction.apply_template_only then
            -- PRN? move this out into its own module, composed with new open_float
            -- log:luaify_trace("predictions.body", body) -- luaify logs later
            log:info("predictions.base_url", FimBackend.base_url)
            log:info("predictions.endpoint", FimBackend.endpoint)

            local response = llama_server_client.apply_template(FimBackend.base_url, body)
            local FloatWindow = require("ask-openai.helpers.float_window")
            local lines = vim.split(response.body.prompt, '\n')
            ---@type FloatWindowOptions
            local opts = { width_ratio = 0.8, height_ratio = 0.8, filetype = "harmony" }
            local buf, win = FloatWindow:new(opts, lines)
            -- PRN? setup harmony grammar for filetype + coloring with treesitter?
            -- PRN? or use LinesBuilder for lines w/ extmarks using LinesBuilder (not hard to do either, and would get me to setup a simple parser!)
            return
        end

        local fim_request = CurlRequest:new({
            body = body,
            base_url = FimBackend.base_url,
            endpoint = FimBackend.endpoint,
            type = "fim",
        })
        this_prediction.fim_request = fim_request

        --- Extracts the appropriate SSE parsing result based on the current FIM backend.
        ---@param sse_parsed table The raw SSE data to be parsed.
        ---@return table sse_result The parsed SSE result.
        local function _extract_sse_fields(sse_parsed)
            if FimBackend.endpoint == CompletionsEndpoints.llamacpp_completions then
                return parse_sse_llamacpp_completions(sse_parsed)
            end
            if FimBackend.endpoint == CompletionsEndpoints.v1_chat_completions then
                return parse_sse_v1_chat_completions(sse_parsed)
            end
            error("Unsupported FIM endpoint: " .. tostring(FimBackend.endpoint))
        end

        ---@type OnParsedSSE
        local function on_parsed_data_sse(sse_parsed)
            performance:token_arrived()
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
                    -- Build both reasoning and content outputs in a single pass
                    local outputs = build_probability_colored_outputs(this_prediction.all_sses)

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
        local function explain_error(text)
            vim.schedule(function()
                -- cannot call nvim_echo in a fast context (which vim.notify uses), happens if not using nvim-notify
                -- note: nvim-notify worked fine in a fast context
                vim.notify("ERROR in new PREDICTIONS FRONTEND PoC: " .. text, vim.log.levels.ERROR)
            end)
        end

        ---@type OnParsedSSE
        local function on_sse_llama_server_timings(sse)
            performance:overall_done()
            stats.show_prediction_stats(sse, performance)
        end

        ---@type StreamingFrontend
        local frontend = {
            on_parsed_data_sse = on_parsed_data_sse,
            on_curl_exited_successfully = on_curl_exited_successfully,
            explain_error = explain_error,
            on_sse_llama_server_timings = on_sse_llama_server_timings,
            -- FYI use closure to capture current context so we don't have to jump through hoops later in saving the trace
            --   I should be able to get current prediction via trace too but let's not deal with it right now
            --   IOTW refactor this crap later when the buffer local predictions is solid and pays dividends
            get_flags_wrapper = function() return PredictionsFrontend.get_flags(params.bufnr) end,
        }

        log:info("Curl.spawn(fim)")
        Curl.spawn(fim_request, frontend)
    end

    if enable_rag and rag_client.is_rag_supported_in_current_file() then
        if not vim.lsp.get_clients({ name = "ask_language_server", bufnr = 0 })[1] then
            -- FYI this check of client ready, must have immaterial overhead for working clients
            --  would be better to do no checks than slow down normal use
            log:error("RAG not available in current LSP, when it should be, so, sending FIM w/o RAG")
            then_send_fim({})
            return
        end
        -- FYI vim.lsp.get_clients is taking ~3us for case when the LSP is operational, imperceptible overhead

        local this_request_ids, cancel -- declare in advance so closure can access
        performance:rag_started()

        ---@param rag_matches LSPRankedMatch[]
        function on_rag_response(rag_matches)
            -- log:info("on_rag_response", vim.inspect(rag_matches))

            -- FYI unroll all rag specific safeguards here so that logic doesn't live inside send_fim
            performance:rag_done()

            -- * make sure prior (canceled) rag request doesn't still respond
            if PredictionsFrontend.rag_request_ids ~= this_request_ids then
                -- I bet this is why sometimes I get completions that still fire even after cancel b/c the RAG results aren't actually stopped in time on server and so they come back
                --  and they arrive after next request started... the mismatch in request_ids will prevent that issue
                log:trace("possibly stale rag results, skipping: " .. vim.inspect({
                    global_rag_request_ids = PredictionsFrontend.rag_request_ids,
                    this_request_ids = this_request_ids,
                }))
                return
            end

            if PredictionsFrontend.rag_cancel == nil then
                log:error("rag appears canceled, skipping on_rag_response...")
                return
            end

            -- clear cancel so not getting cancel message after retrieval (on next keystroke)
            PredictionsFrontend.rag_cancel = nil
            PredictionsFrontend.rag_request_ids = nil

            then_send_fim(rag_matches)
        end

        PredictionsFrontend.rag_cancel = function()
            log:warn("canceling RAG")
            PredictionsFrontend.rag_cancel = nil
            cancel()
            PredictionsFrontend.rag_request_ids = nil
        end
        this_request_ids, cancel = rag_client.context_query_fim(ps_chunk, on_rag_response)
        -- log:info("after context_query_fim started")
        PredictionsFrontend.rag_request_ids = this_request_ids
    else
        PredictionsFrontend.rag_cancel = nil
        PredictionsFrontend.rag_request_ids = nil
        then_send_fim({})
    end
end

--- @param bufnr integer
function PredictionsFrontend.cancel_current_prediction(bufnr)
    -- PRN stdout/stderr:read_stop() to halt on_stdout/stderr callbacks from firing again (before handle:close())?!
    if PredictionsFrontend.rag_cancel then
        PredictionsFrontend.rag_cancel()
    end
    local this_prediction = PredictionsFrontend._get_current_prediction(bufnr)
    if not this_prediction then
        return
    end
    PredictionsFrontend._set_current_prediction(bufnr, nil)
    this_prediction:mark_as_abandoned()

    vim.schedule(function()
        this_prediction:clear_extmarks()
    end)

    -- FYI both this_prediction and request are new with each keystroke
    CurlRequest.terminate(this_prediction.fim_request)
end

function PredictionsFrontend.get_flags(bufnr)
    local flags = {}
    local current = PredictionsFrontend._get_current_prediction(bufnr)
    if current and current.has_duplicate_prefix then
        flags["fim_duplicate_prefix"] = current._trace_only_duplicate_prefix
    end
    return flags
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
local keypresses_subscription = keypresses:subscribe(function(event)
    --- @cast event ObservableKeyPressEvent

    -- immediately clear/hide prediction, else slides as you type
    -- TODO schedule or not?
    vim.schedule(function()
        log:info("keypress", event.bufnr)
        PredictionsFrontend.cancel_current_prediction(event.bufnr)
    end)
end)
local debounced_subscription = debounced:subscribe(function(event)
    --- @cast event ObservableKeyPressEvent
    log:info("debounced", event.bufnr)
    vim.schedule(function()
        -- log:trace("CursorMovedI debounced")

        if vim.fn.mode() ~= "i" then
            return
        end

        PredictionsFrontend.ask_for_prediction({ bufnr = event.bufnr })
    end)
end)

function PredictionsFrontend.cursor_moved_in_insert_mode(bufnr)
    local current_prediction = PredictionsFrontend._get_current_prediction(bufnr)
    if current_prediction and current_prediction.disable_cursor_moved == true then
        -- log:trace("Disabled CursorMovedI, skipping...")
        current_prediction.disable_cursor_moved = false -- skip once
        -- called after accepting/inserting text (AFAICT only once per accept)
        return
    end

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

    keypresses:onNext({ bufnr = bufnr })
end

---@param event vim.api.keyset.create_autocmd.callback_args
function PredictionsFrontend.leaving_insert_mode(event)
    log:info("leaving_insert_mode", event.buf)
    PredictionsFrontend.cancel_current_prediction(event.buf)
end

---@param event vim.api.keyset.create_autocmd.callback_args
function PredictionsFrontend.entering_insert_mode(event)
    log:info("entering_insert_mode", event)
    PredictionsFrontend.cursor_moved_in_insert_mode(event.buf)
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
    PredictionsFrontend.cursor_moved_in_insert_mode(bufnr)
end

function PredictionsFrontend.vim_is_quitting(event)
    local bufnr = vim.fn.bufnr()
    -- TODO wire up, this is valuable if a long running FIM is left to keep going even after neovim shutsdown
    log:info("vim_is_quitting", bufnr)
    PredictionsFrontend.cancel_current_prediction(bufnr)
end

local are_predictions_running = false

local augroup = "ask-openai.prediction"

local keymap_accept_all = '<Tab>'
local keymap_accept_line = '<C-right>'
local keymap_accept_word = '<M-right>'
local keymap_redo_prediction = '<M-Tab>'

function PredictionsFrontend.start_predictions()
    if are_predictions_running then
        return
    end

    local predictions_frontend = require("ask-openai.predictions.frontend")

    -- hardcoded keymaps
    vim.api.nvim_set_keymap('i', keymap_accept_all, "",
        { noremap = true, callback = predictions_frontend.accept_all_invoked })

    vim.api.nvim_set_keymap('i', keymap_accept_line, "",
        { noremap = true, callback = predictions_frontend.accept_line_invoked })

    vim.api.nvim_set_keymap('i', keymap_accept_word, "",
        { noremap = true, callback = predictions_frontend.accept_word_invoked })

    vim.api.nvim_set_keymap('i', keymap_redo_prediction, "",
        { noremap = true, callback = predictions_frontend.new_prediction_invoked })

    -- vim.keymap.set("n", "<leader>~", "<cmd>AskDumpEdits<CR>", {})

    function trigger_apply_template_dump()
        local bufnr = vim.fn.bufnr()
        log:info("trigger_apply_template_dump", bufnr)
        predictions_frontend.ask_for_prediction({
            bufnr = bufnr,
            apply_template_only = true,
        })
    end

    vim.keymap.set("n", "<leader>temp", trigger_apply_template_dump, {})

    -- event subscriptions
    vim.api.nvim_create_augroup(augroup, { clear = true })
    vim.api.nvim_create_autocmd("InsertLeavePre", {
        group = augroup,
        pattern = "*",
        callback = predictions_frontend.leaving_insert_mode
    })
    vim.api.nvim_create_autocmd("InsertEnter", {
        group = augroup,
        pattern = "*",
        callback = predictions_frontend.entering_insert_mode
    })
    -- vim.api.nvim_create_autocmd("CursorMovedI", {
    --     -- TODO TextChangedI intead of cursor moved?
    --     group = augroup,
    --     pattern = "*", -- todo filter?
    --     callback = predictions_frontend.cursor_moved_in_insert_mode
    -- })
    vim.api.nvim_create_autocmd("TextChangedI", {
        -- FYI been using this for a LONG time now and no issues (AFAICT)
        group = augroup,
        pattern = "*",
        callback = function(event)
            ---@cast event vim.api.keyset.create_autocmd.callback_args
            predictions_frontend.cursor_moved_in_insert_mode(event.buf)
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
    pcall(vim.api.nvim_del_augroup_by_name, augroup) -- most del methods will throw if doesn't exist... so just ignore that

    -- remove keymaps (using same hardcoded values)
    pcall(vim.api.nvim_del_keymap, 'i', keymap_accept_all)
    pcall(vim.api.nvim_del_keymap, 'i', keymap_accept_line)
    pcall(vim.api.nvim_del_keymap, 'i', keymap_accept_word)
    pcall(vim.api.nvim_del_keymap, 'i', keymap_redo_prediction)

    are_predictions_running = false
end

function PredictionsFrontend.setup()
    if config.local_share.are_predictions_enabled() then
        PredictionsFrontend.start_predictions()
    end
end

return PredictionsFrontend
