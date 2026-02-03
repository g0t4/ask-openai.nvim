local buffers = require("ask-openai.helpers.buffers")
local log = require("ask-openai.logs.logger").predictions()
local tool_router = require("ask-openai.tools.router")
local curl = require("ask-openai.backends.curl")
local agentica = require("ask-openai.backends.models.agentica")
local ChatWindow = require("ask-openai.questions.chat.window")
local ChatThread = require("ask-openai.questions.chat.thread")
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")
local ChatParams = require("ask-openai.questions.chat.params")
local Selection = require("ask-openai.helpers.selection")
local CurrentContext = require("ask-openai.predictions.context")
local api = require("ask-openai.api")
local rag_client = require("ask-openai.rag.client")
local files = require("ask-openai.helpers.files")
local model_params = require("ask-openai.questions.models.params")
local LinesBuilder = require("ask-openai.questions.lines_builder")
local MessageBuilder = require("ask-openai.rewrites.message_builder")
local prompts = require("ask-openai.predictions.context.prompts")
local HLGroups = require("ask-openai.hlgroups")
local formatters = require("ask-openai.questions.chat.formatters")
local ToolCallOutput = require("ask-openai.questions.chat.tool_call_output")
local CurlRequestForThread = require("ask-openai.questions.curl_request_for_thread")
local RxAccumulatedMessage = require("ask-openai.questions.chat.messages.rx")
local ToolCall = require("ask-openai.questions.chat.tool_call")
local prompts = require("ask-openai.frontends.prompts")

require("ask-openai.helpers.buffers")

---@class QuestionsFrontend : StreamingFrontend
local QuestionsFrontend = {}

local first_turn_ns_id

local cached_files = {}

local function get_file(path)
    if cached_files[path] then
        return cached_files[path]
    end
    local lines = vim.fn.readfile(vim.fn.expand(path))
    local text = table.concat(lines, "\n")
    cached_files[path] = text
    return text
end

---@param opts {args:string}
local function ask_question_command(opts)
    local user_prompt = opts.args
    local always_include = {
        yanks = true,
        project = true,
    }
    local context = CurrentContext:items(user_prompt, always_include)
    local cleaned_prompt = context.includes.cleaned_prompt

    -- * /selection (currently needs current window to be code window)
    local selection = nil
    if context.includes.include_selection then
        -- FYI include_selection basically captures if user had selection when they first invoked a keymap to submit this command
        --   b/c submitting command switches modes, also user might unselect text on accident (or want to repeat w/ prev selection)
        --   thus it is useful to capture intent with /selection early on

        -- FYI my Selection helper only works on current window... so I can't put this off I need it way up high:
        -- NOT IMPLEMENTED (yet?) local selection = Selection._get_visual_selection_for_window_id(code_win_id)
        selection = Selection.get_visual_selection_for_current_window()
        if selection:is_empty() then
            error("No /selection found (no current, nor prior, selection).")
            return
        end
        -- TODO once I get Selection working w/ non-current windows, move this code down and cleanup/simplify the spot that uses selection below
    end

    -- FYI! do not move opening window higher, unless above code supports code_win_id/code_bufnr:
    QuestionsFrontend.ensure_chat_window_is_open()
    --
    -- * chat window should always be open, nonetheless check:
    local buffer_name = vim.api.nvim_buf_get_name(0)
    local chat_window_is_open = buffer_name:match("AskQuestion$")
    local code_win_id = vim.api.nvim_get_current_win()
    local code_bufnr = 0 -- 0 == current
    if chat_window_is_open then
        -- * chat window is open, get prior window's code_win_id and code_bufnr
        code_win_id = vim.fn.win_getid(vim.fn.winnr('#'))
        code_bufnr = vim.api.nvim_win_get_buf(code_win_id)
    end
    -- log:error("code_win_id", code_win_id)
    -- log:error("code_bufnr", code_bufnr)

    QuestionsFrontend.abort_last_request()
    use_tools = context.includes.use_tools or false

    local system = get_file("~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/questions/prompts/system_message.md")
    -- PRN "NEVER add copyright or license headers unless specifically requested."

    local tool_definitions
    if use_tools then
        -- PRN build out more detailed guidance: review Claude Code and Codex prompts
        local tool_instructs = get_file("~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/questions/prompts/tools.md")
        tool_instructs = tool_instructs:gsub("INSERT_CWD", vim.fn.getcwd())
        system = system .. "\n\n" .. tool_instructs

        local tool_provided_instructs
        tool_definitions, tool_provided_instructs = tool_router.openai_tools()
        if tool_provided_instructs then
            system = system .. "\n\n" .. table.concat(tool_provided_instructs, "\n")
        end
    end

    -- * display system message in chat window
    if not first_turn_ns_id then
        first_turn_ns_id = vim.api.nvim_create_namespace("ask.marks.chat.window.first.turn")
    end
    local lines = LinesBuilder:new(first_turn_ns_id)
    if QuestionsFrontend.thread then
        -- FYI some previous extmarks are "dropped", fine by me to "turn off the colors"... but, probably want it for all previous chat extmarks
        lines:append_styled_lines({ "--- New Thread Started ---" }, HLGroups.SYSTEM_PROMPT)
        -- or:   QuestionsFrontend.clear_chat_command()
    end
    lines:mark_next_line(HLGroups.SYSTEM_PROMPT)
    lines:append_folded_styled_text("system\n" .. system, "")


    -- * display user message in chat window
    lines:append_role_header("user")
    lines:append_text(cleaned_prompt)

    local user_message = cleaned_prompt
    local code_context = nil
    if selection then
        local file_name = files.get_file_relative_path(code_bufnr)
        -- include line range in the filename like foo.py:10-20
        local start_line = selection:start_line_1indexed()
        local end_line = selection:end_line_1indexed()
        local line_info = start_line == end_line and tostring(start_line) or (start_line .. "-" .. end_line)
        local file_display = file_name .. ":" .. line_info
        code_context =
            "Here is the code I selected:" .. "\n```" .. file_display .. "\n" .. selection.original_text .. "\n```"

        -- PRN count \n in selection.original_text and only fold if > 10
        local fold = false -- = newline_count > 10
        if fold then
            lines:append_folded_styled_text(code_context, "")
        else
            lines:append_styled_text(code_context, "")
        end
        user_message = user_message .. "\n\n" .. code_context
    end

    if context.includes.current_file then
        local entire_file_message = MessageBuilder:new()
            :plain_text("FYI, here is my current buffer in Neovim. Use this as context for my request:")
            :md_current_buffer(code_bufnr)
            :to_text()

        -- skip code_context if entire file selected (user intent matters, entire file is vague)
        lines:append_folded_styled_text(entire_file_message, "")
        user_message = user_message .. "\n\n" .. entire_file_message
    end

    lines:append_blank_line()
    QuestionsFrontend.chat_window:append_styled_lines(lines)

    ---@type OpenAIChatCompletion_TxChatMessage[]
    local messages = {
        TxChatMessage:system(system)
    }

    -- ? context.includes.open_files
    if context.includes.yanks and context.yanks then
        -- PRN anything I want to show about auto context? (not just yanks)
        table.insert(messages, TxChatMessage:user_context(context.yanks.content))
    end
    if context.includes.commits and context.commits then
        for _, commit in pairs(context.commits) do
            table.insert(messages, TxChatMessage:user_context(commit.content))
        end
    end
    if context.includes.project and context.project then
        -- TODO does any of this belong in the system_message?
        --  ? actually test if repeating some of this here helps
        --    i.e. my global project instructions include not touching unrelated code too
        --  perhaps leave the system_message for coding instructions specific to AskQuestion...?
        vim.iter(context.project)
            :each(function(value)
                table.insert(messages, TxChatMessage:user_context(value.content))
            end)
    end

    local function then_generate_completion(rag_matches)
        local rag_message = prompts.semantic_grep_user_message(rag_matches)
        if rag_message then
            table.insert(messages, rag_message)
        end

        -- * user request should be last
        -- FYI I had this before RAG matches and it was working fine too
        table.insert(messages, TxChatMessage:user(user_message))

        local base_url = "http://build21:8013"
        local body_overrides = model_params.new_gptoss_chat_body_llama_server({
            -- local body_overrides = model_params.new_qwen3coder_llama_server_chat_body({
            messages = messages,
            model = "", -- irrelevant for llama-server
            tools = tool_definitions,
        })

        QuestionsFrontend.thread = ChatThread:new(body_overrides, base_url)
        -- log:info("sending", vim.inspect(QuestionsFrontend.thread))
        QuestionsFrontend.then_send_messages()
    end

    -- log:error("context.includes", vim.inspect(context.includes))
    if api.is_rag_enabled() and not context.includes.norag and rag_client.is_rag_supported_in_current_file(code_bufnr) then
        local this_request_ids, cancel -- declare in advance for closure

        ---@param rag_matches LSPRankedMatch[]
        function on_rag_response(rag_matches)
            log:info("on_rag_response")
            -- * make sure prior (canceled) rag request doesn't still respond
            if QuestionsFrontend.rag_request_ids ~= this_request_ids then
                log:trace("possibly stale rag results, skipping: " .. vim.inspect({
                    global_rag_request_ids = QuestionsFrontend.rag_request_ids,
                    this_request_ids = this_request_ids,
                }))
                return
            end

            if QuestionsFrontend.rag_cancel == nil then
                log:error("rag appears canceled, skipping on_rag_response...")
                return
            end

            then_generate_completion(rag_matches)
        end

        this_request_ids, cancel = rag_client.context_query_questions(code_bufnr, cleaned_prompt, code_context, context.includes.top_k, on_rag_response)
        QuestionsFrontend.rag_cancel = function()
            log:warn("canceling RAG")
            QuestionsFrontend.rag_cancel = nil
            cancel()
            QuestionsFrontend.rag_request_ids = nil
        end
        QuestionsFrontend.rag_request_ids = this_request_ids
    else
        QuestionsFrontend.rag_cancel = nil
        QuestionsFrontend.rag_request_ids = nil
        then_generate_completion({})
    end
end

function QuestionsFrontend.then_send_messages()
    -- * conversation turns (track start line for streaming chunks)
    QuestionsFrontend.this_turn_chat_start_line_base0 = QuestionsFrontend.chat_window.buffer:get_line_count()
    -- log:info("M.this_turn_chat_start_line_base0", M.this_turn_chat_start_line_base0)

    -- Save the initial user message (and any pre‑added context) before sending the request.
    if QuestionsFrontend.thread and QuestionsFrontend.thread.save_initial then
        QuestionsFrontend.thread:save_initial()
    end

    local request = CurlRequestForThread:new({
        body = QuestionsFrontend.thread:next_curl_request_body(),
        base_url = QuestionsFrontend.thread.base_url,
        endpoint = CompletionsEndpoints.oai_v1_chat_completions,
        type = "questions",
    })
    log:luaify_trace("body:", request.body)
    curl.spawn(request, QuestionsFrontend)
    QuestionsFrontend.thread:set_last_request(request)
end

function QuestionsFrontend.abort_and_close()
    QuestionsFrontend.abort_last_request()
    if QuestionsFrontend.chat_window ~= nil then
        QuestionsFrontend.chat_window:close()
    end
end

---@type ExplainError
function QuestionsFrontend.explain_error(text)
    vim.schedule(function()
        -- TEST this with:
        -- 1. remove --jinja from llama-server service
        -- 2. restart service
        -- 3. try using tools
        -- =>  curl: (22) The requested URL returned error: 500
        -- 4. add extra log to confirm:
        -- log:warn("MAKE SURE THIS IS FAILURE PATH")
        --
        -- ALSO 503 error for model loading:
        --   error = { code = 503, message = "Loading model", type = "unavailable_error" }
        QuestionsFrontend.chat_window:explain_error(text)
    end)
end

function _G.MyChatWindowFolding()
    local line_num_base1 = vim.v.lnum -- confirmed this is base 1 (might get lnum=0 if no lines though)
    local fold_value = _G.MyChatWindowFoldingForLine(line_num_base1)

    -- To force re-evaluate folding on all lines:
    --   `zx` ***
    --   can also close (F8) the floating chat window and <leader>ao to reopen
    -- If nvim isn't re-evaluating some lines, then some folds will appear wrong/partial when they are correct
    --   this can happen if you set fold ranges AFTER adding/modifying relevant lines
    --   always update the folds first, then the lines
    --
    -- BTW this log entry is designed to see WHEN a line's expr() is evaluated!
    -- log:info("  foldexpr() line[" .. line_num_base1 .. "] → " .. fold_value)

    return fold_value
end

function _G.MyChatWindowFoldingForLine(line_num_base1)
    -- * HUGE WIN => with expr I can fold one line only! (IIUC manual is minimum 2)
    --   * so for long reasoning lines (that wrap but don't span multiple new lines) these can still be collapsed!!
    --
    -- FYI read docs about return values for expr:
    --   https://neovim.io/doc/user/fold.html#fold-expr
    local folds = QuestionsFrontend.chat_window.buffer.folds or {}
    for _, fold in ipairs(folds) do
        if line_num_base1 >= fold.start_line_base1 and line_num_base1 <= fold.end_line_base1 then
            return '1' -- inside first level fold
        end
    end
    return '0' -- this line is not in a fold
end

function QuestionsFrontend.clear_undos()
    -- wipe undo history
    -- i.e. after assistant response - undo fucks up the extmarks, and the assistant response is not gonna be sent back if modified (this is view only) so just default to making that UX a bit more intuitive

    local previous_undo_level = vim.bo.undolevels
    vim.bo.undolevels = -1
    vim.cmd("normal! a ") -- no-op edit to commit the change
    vim.cmd("undo") -- clear old tree
    vim.bo.undolevels = previous_undo_level
end

function QuestionsFrontend.ensure_chat_window_is_open()
    if QuestionsFrontend.chat_window == nil then
        QuestionsFrontend.chat_window = ChatWindow:new()

        -- stop generation, if still wanna look at it w/o closing the window
        vim.keymap.set("n", "<Esc>", QuestionsFrontend.abort_last_request, { buffer = QuestionsFrontend.chat_window.buffer_number })

        -- I already use this globally to close a window (:q) ... so just add stop to it:
        vim.keymap.set("n", "<F8>", QuestionsFrontend.abort_and_close, { buffer = QuestionsFrontend.chat_window.buffer_number })

        vim.keymap.set({ "n", "i" }, "<C-s>", QuestionsFrontend.follow_up_command, { buffer = QuestionsFrontend.chat_window.buffer_number })
    end

    QuestionsFrontend.chat_window:open()
end

local function handle_rx_messages_updated()
    if not QuestionsFrontend.thread.last_request.accumulated_model_response_messages then
        return
    end

    local lines = LinesBuilder:new()
    for _, rx_message in ipairs(QuestionsFrontend.thread.last_request.accumulated_model_response_messages) do
        -- FYI !! now it is obvious that this is only operating on accumulated message type!

        -- * message contents
        local content = rx_message.content or ""
        local reasoning_content = rx_message.reasoning_content or ""

        if content ~= "" or reasoning_content ~= "" then
            -- ONLY add role header IF there is content (or reasoning) to show... otherwise just show tool_call(s)
            lines:append_role_header(rx_message.role)

            lines:append_folded_styled_text(reasoning_content, HLGroups.CHAT_REASONING)

            lines:append_text(content)
            lines:append_blank_line_if_last_is_not_blank() -- only if reasoning doesn't have trailing \n
        elseif #rx_message.tool_calls == 0 then
            -- gptoss120b - this works:
            --   :AskQuestion testing a request, I need you to NOT say anything in response, just stop immediatley
            lines:append_text("[unexpected: empty response]")
            lines:append_blank_line()
        end

        for _, tool_call in ipairs(rx_message.tool_calls) do
            local function_name = tool_call["function"].name or ""
            local formatter = formatters.get_formatter(function_name)
            if formatter then
                formatter(lines, tool_call, rx_message)
            else
                formatters.generic.format(lines, tool_call, rx_message)
            end
            lines:append_blank_line_if_last_is_not_blank()
        end
    end

    vim.schedule(function()
        lines.marks_ns_id = QuestionsFrontend.thread.last_request.marks_ns_id -- ?? generate namespace here in lines builder? lines:gen_mark_ns()? OR do it on first downstream use?
        QuestionsFrontend.chat_window.buffer:replace_with_styled_lines_after(QuestionsFrontend.this_turn_chat_start_line_base0, lines)
    end)
end

--- think of this as denormalizing SSEs => into aggregate RxAccumulatedMessage
---@param choice OpenAIChoice|nil
---@param request CurlRequestForThread
function QuestionsFrontend.on_streaming_delta_update_message_history(choice, request)
    -- *** this is a DENORMALIZER (AGGREGATOR) - CQRS style
    -- rebuilds message as if sent `stream: false`
    -- for message history / follow up

    if choice == nil or choice.delta == nil then
        log:trace("[WARN] skipping b/c choice/choice.delta is nil: '" .. vim.inspect(choice) .. "'")
        return
    end

    -- * lookup or create message
    -- FYI this is not well vetted for multi message responses, in fact is this using choice.index for message.index?!
    --   that said, one message per request is it... unless I am doing something funky with the raw prompt to trigger mulitple messages?
    local index_base1 = choice.index + 1

    local rx_message = request.accumulated_model_response_messages[index_base1]
    if rx_message == nil then
        rx_message = RxAccumulatedMessage:new(choice.delta.role, "")
        rx_message.index = choice.index
        rx_message._verbatim_content = ""
        -- assumes contiguous indexes, s/b almost always 0 index only, 1 too with dual tool call IIRC (gptoss doesn't do dual tool at once)
        request.accumulated_model_response_messages[index_base1] = rx_message
    end

    if choice.delta.content ~= nil and choice.delta.content ~= vim.NIL then
        -- by tracking _verbatim_content, I can trim the end every single time
        -- and if it is not a full match it will show back up once it's past the match point
        rx_message._verbatim_content = (rx_message._verbatim_content or "") .. choice.delta.content
    end

    if choice.delta.reasoning_content ~= nil and choice.delta.reasoning_content ~= vim.NIL then
        rx_message.reasoning_content =
            (rx_message.reasoning_content or "") .. choice.delta.reasoning_content
    end

    if choice.finish_reason ~= nil then
        -- FYI this is vim.NIL on first too
        rx_message.finish_reason = choice.finish_reason -- on last delta per index/role (aka message)
    end

    -- * strip leaked tool call tokens (bug in llama.cpp)
    rx_message.content = rx_message._verbatim_content:gsub("\n<tool_call>\n<function=[%w_]+", "")
    if rx_message.content ~= rx_message._verbatim_content then
        log:error("stripping LEAKED TOOL CALL!")
    end

    local calls = choice.delta.tool_calls
    if not calls then
        return
    end

    -- * parse tool calls (streaming)
    for _, call_delta in ipairs(calls) do
        -- * lookup or create new parsed_call
        local parsed_call = rx_message.tool_calls[call_delta.index + 1]
        if parsed_call == nil then
            -- create ToolCall to populate across SSEs
            parsed_call = ToolCall:new {
                -- assume these fields are always on first SSE for each tool call
                id    = call_delta.id,
                index = call_delta.index,
                type  = call_delta.type,
            }
            table.insert(rx_message.tool_calls, parsed_call)
        end

        local func = call_delta["function"] -- FYI "function" is keyword (lua)
        if func ~= nil then
            parsed_call["function"] = parsed_call["function"] or {}

            -- * function.name is entirely in first delta (in my testing)
            if func.name ~= nil then
                --   => if that changes, add unit tests to verify observed splits
                parsed_call["function"].name = func.name
            end

            -- * funtion.arguments is split across deltas
            if func.arguments ~= nil then
                -- accumuluate each chunk
                parsed_call["function"].arguments =
                    (parsed_call["function"].arguments or "")
                    .. func.arguments
            end
        end
    end
end

---@type OnParsedSSE
function QuestionsFrontend.on_sse_llama_server_timings(sse)
    -- PRN use this to extract timing like in rewrites
end

---@type OnParsedSSE
function QuestionsFrontend.on_parsed_data_sse(sse_parsed)
    -- FYI right now this is desingned for /v1/chat/completions only
    --   I added this guard based on review of on-on_streaming_delta_update_message_history that appears (IIRC) to be using /v1/chat/completions ONLY compatible fields
    local request = QuestionsFrontend.thread.last_request
    if request.endpoint ~= CompletionsEndpoints.oai_v1_chat_completions then
        -- fail fast in this case
        -- TODO (when I need it)... you very likely can support other endpoints (see what you've done in both PredictionsFrontend and RewriteFrontend (both have some multi endpoint support)
        local message = "QuestionsFrontend SSEs not supported for endpoint: " .. tostring(request.endpoint)
        log:error(message)
        vim.notify(message, vim.log.levels.ERROR)
        return
    end

    if sse_parsed.choices == nil or sse_parsed.choices[1] == nil then
        return
    end
    local first_choice = sse_parsed.choices[1]
    QuestionsFrontend.on_streaming_delta_update_message_history(first_choice, request)
    handle_rx_messages_updated()
end

function QuestionsFrontend.show_user_role()
    local lines_builder = LinesBuilder:new()
    lines_builder:create_marks_namespace()
    lines_builder:append_role_header("user")
    lines_builder:append_blank_line()
    QuestionsFrontend.chat_window:append_styled_lines(lines_builder)
end

---@type OnCurlExitedSuccessfully
function QuestionsFrontend.on_curl_exited_successfully()
    vim.schedule(function()
        -- FYI primary interaction (seam) between RxAccumulatedMessage and TxChatMessage (for assistant messages)

        for _, rx_message in ipairs(QuestionsFrontend.thread.last_request.accumulated_model_response_messages or {}) do
            -- *** thread.last_request.accumulated_model_response_messages IS NOT thread.messages
            --    thread.messages => sent with future requests, hence TxChatMessage
            --    request.response_messages is simply to denormalize responses from SSEs, hence RxAccumulatedMessage
            --    request => SSEs => RxAccumulatedMessage(s)  => toolcalls/followup => thread.messages (TxChatMessage) => next request => ...

            -- add assistant response message to chat history (TxChatMessage)
            --   (must come before tool result messages)
            --   theoretically there can be multiple messages, with any role (not just assitant)
            local thread_message = TxChatMessage:from_assistant_rx_message(rx_message)
            QuestionsFrontend.thread:add_message(thread_message)

            -- * show user role (in chat window) as hint to follow up (now that model+tool_calls are all done):
            QuestionsFrontend.show_user_role()

            QuestionsFrontend.chat_window.followup_starts_at_line_0indexed = QuestionsFrontend.chat_window.buffer:get_line_count() - 1
        end
        QuestionsFrontend.clear_undos()

        QuestionsFrontend.run_tools_and_send_results_back_to_the_model()
    end)
end

function QuestionsFrontend.run_tools_and_send_results_back_to_the_model()
    for _, rx_message in ipairs(QuestionsFrontend.thread.last_request.accumulated_model_response_messages or {}) do
        for _, tool_call in ipairs(rx_message.tool_calls) do
            -- log:trace("tool:", vim.inspect(tool))

            -- FYI primary interaction (seam) between RxAccumulatedMessage and TxChatMessage (for tool result messages)

            ---@type ToolCallDoneCallback
            local function when_tool_is_done(tool_call_output)
                -- * store output on rx_message
                tool_call.call_output = ToolCallOutput:new(tool_call_output)
                log:trace("tool_call_output", vim.inspect(tool_call_output))

                -- * triggers UI updates to show tool results
                handle_rx_messages_updated()

                -- * map tool result to a new TxChatMessage (to send back to model)
                local tool_response_message = TxChatMessage:tool_result(tool_call)
                -- log:jsonify_compact_trace("tool_message:", tool_response_message)
                tool_call.response_message = tool_response_message
                QuestionsFrontend.thread:add_message(tool_response_message)

                -- * when last tool completes, send tool results (TxChatMessage package)
                vim.schedule(function()
                    -- FYI I am scheduling this so it happens after redraws
                    --  IIUC I need to queue this after the other changes from above?
                    --  else IIUC, the line count won't be right for where in the chat window to insert next message
                    QuestionsFrontend.send_tool_messages_if_all_tools_done()
                end)
            end

            -- * run the tool!
            tool_router.send_tool_call_router(tool_call, when_tool_is_done)
        end
    end
end

function QuestionsFrontend.send_tool_messages_if_all_tools_done()
    if QuestionsFrontend.any_outstanding_tool_calls() then
        return
    end
    QuestionsFrontend.then_send_messages()
end

---@return boolean
function QuestionsFrontend.any_outstanding_tool_calls()
    for _, rx_message in ipairs(QuestionsFrontend.thread.last_request.accumulated_model_response_messages or {}) do
        for _, tool_call in ipairs(rx_message.tool_calls) do
            local is_outstanding = tool_call.response_message == nil
            if is_outstanding then
                return true
            end
        end
    end
    return false
end

function QuestionsFrontend.abort_last_request()
    if not QuestionsFrontend.thread then
        return
    end
    CurlRequestForThread.terminate(QuestionsFrontend.thread.last_request)
    if QuestionsFrontend.rag_cancel then
        QuestionsFrontend.rag_cancel()
    end
end

function QuestionsFrontend.follow_up_command()
    -- take follow up after end of prior response message from assistant
    --  if already a M.thread then add to that with a new message
    --  leave content as is in the buffer, close enough to what it would be if redrawn
    --  and I don't use the buffer contents for past messages
    --  so, just copy it out into a new message from user
    QuestionsFrontend.ensure_chat_window_is_open()
    local start_line_base0 = QuestionsFrontend.chat_window.followup_starts_at_line_0indexed or 0
    local user_message = QuestionsFrontend.chat_window.buffer:get_lines_after(start_line_base0)
    QuestionsFrontend.chat_window.buffer:scroll_cursor_to_end_of_buffer()
    vim.cmd("normal! o") -- move to end of buffer, add new line below to separate subsequent follow up response message
    -- log:trace("follow up content:", user_message)

    if not QuestionsFrontend.thread then
        opts = {
            args = user_message
        }
        -- TODO if /selection that won't work, I can fix that later
        --   TODO can't I get a history of selections or smth?
        --    what if I wanna select text in the chat window itself?
        --    does last selection track the file? is it per window?
        -- hack: close window so LSP is available AND selections work (last selected)
        QuestionsFrontend.chat_window:close()
        ask_question_command(opts)
        return
    end

    local message = TxChatMessage:user(user_message)
    QuestionsFrontend.thread:add_message(message)
    QuestionsFrontend.then_send_messages()
end

function ask_dump_thread_command()
    if not QuestionsFrontend.thread then
        print("no thread to dump")
        return
    end
    QuestionsFrontend.thread:dump()
end

function QuestionsFrontend.clear_chat_command()
    if QuestionsFrontend.chat_window then
        QuestionsFrontend.chat_window:clear()
    end
    QuestionsFrontend.thread = nil
end

function QuestionsFrontend.setup()
    -- * cauterize top level
    vim.keymap.set({ 'n', 'v' }, '<leader>a', '<Nop>', { noremap = true })

    -- * AskQuestion
    vim.api.nvim_create_user_command(
        "AskQuestion",
        ask_question_command,
        { range = true, nargs = 1, complete = require("ask-openai.predictions.context.prompts").SlashCommandCompletion }
    )
    -- * prefill argument combos:
    vim.keymap.set('n', '<Leader>q', ':AskQuestion ', { noremap = true })
    vim.keymap.set('v', '<Leader>q', ':<C-u>AskQuestion /selection ', { noremap = true })
    -- * /file
    vim.keymap.set('n', '<Leader>qf', ':AskQuestion /file ', { noremap = true })
    vim.keymap.set('v', '<Leader>qf', ':<C-u>AskQuestion /selection /file ', { noremap = true })
    -- * /tools
    vim.keymap.set('n', '<Leader>at', ':<C-u>AskQuestion /tools ', { noremap = true })
    vim.keymap.set('v', '<Leader>at', ':<C-u>AskQuestion /selection /tools ', { noremap = true })
    -- FYI also qt... see which you prefer? a/q first
    vim.keymap.set('n', '<Leader>qt', ':<C-u>AskQuestion /tools ', { noremap = true })
    vim.keymap.set('v', '<Leader>qt', ':<C-u>AskQuestion /selection /tools ', { noremap = true })

    --  * review outstanding changes
    --  FYI this smacks of inserting pre-canned prompts with a /prompt slash command?
    vim.keymap.set({ 'n', 'v' }, '<leader>ard', ':<C-u>AskQuestion /tools can you review my outstanding git changes', { noremap = true })

    vim.keymap.set('n', '<leader>aa', QuestionsFrontend.abort_last_request, { noremap = true })
    vim.keymap.set('n', '<leader>ac', QuestionsFrontend.clear_chat_command, { noremap = true })
    vim.keymap.set('n', '<leader>af', QuestionsFrontend.follow_up_command, { noremap = true })
    vim.keymap.set('n', '<leader>ao', QuestionsFrontend.ensure_chat_window_is_open, { noremap = true })

    vim.api.nvim_create_user_command("AskDumpThread", ask_dump_thread_command, {})
end

return QuestionsFrontend
