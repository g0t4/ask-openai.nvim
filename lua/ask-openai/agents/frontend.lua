local buffers = require("ask-openai.helpers.buffers")
local log = require("ask-openai.logs.logger").predictions()
local completion_logger = require("ask-openai.logs.completion_logger")
local tool_router = require("ask-openai.tools.router")
local curl = require("ask-openai.backends.curl")
local agentica = require("ask-openai.backends.models.agentica")
local AgentWindow = require("ask-openai.agents.viewer.window")
local AgentTrace = require("ask-openai.agents.trace")
local TxChatMessage = require("ask-openai.agents.messages.tx")
local Selection = require("ask-openai.helpers.selection")
local CurrentContext = require("ask-openai.frontends.context")
local api = require("ask-openai.api")
local rag_client = require("ask-openai.rag.client")
local files = require("ask-openai.helpers.files")
local model_params = require("ask-openai.agents.models.params")
local LinesBuilder = require("ask-openai.agents.viewer.lines_builder")
local MessageBuilder = require("ask-openai.rewrites.message_builder")
local prompt_parser = require("ask-openai.frontends.context.prompt_parser")
local HLGroups = require("ask-openai.hlgroups")
local formatters = require("ask-openai.agents.viewer.formatters")
local ToolCallOutput = require("ask-openai.agents.tools.tool_call_output")
local CurlRequestForTrace = require("ask-openai.agents.curl_request_for_trace")
local RxAccumulatedMessage = require("ask-openai.agents.messages.rx")
local ToolCall = require("ask-openai.agents.tools.tool_call")
local rag_instructions = require("ask-openai.frontends.prompts.rag_instructions")
local inspect = require("devtools.inspect")

require("ask-openai.helpers.buffers")

---@class AgentsFrontend : StreamingFrontend
local AgentsFrontend = {}

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
local function ask_agent_command(opts)
    local user_prompt = opts.args
    local always_include = {
        yanks = true,
        project = true,
    }
    local context = CurrentContext:items(user_prompt, always_include)
    local cleaned_prompt = context.includes.rendered_prompt

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
    AgentsFrontend.ensure_chat_window_is_open()
    --
    -- * chat window should always be open, nonetheless check:
    local buffer_name = vim.api.nvim_buf_get_name(0)
    local chat_window_is_open = buffer_name:match("AskAgent$")
    local code_win_id = vim.api.nvim_get_current_win()
    local code_bufnr = 0 -- 0 == current
    if chat_window_is_open then
        -- * chat window is open, get prior window's code_win_id and code_bufnr
        code_win_id = vim.fn.win_getid(vim.fn.winnr('#'))
        code_bufnr = vim.api.nvim_win_get_buf(code_win_id)
    end
    -- log:error("code_win_id", code_win_id)
    -- log:error("code_bufnr", code_bufnr)

    AgentsFrontend.abort_last_request()
    use_tools = context.includes.use_tools or false

    local system = get_file("~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/agents/prompts/system_message.md")
    -- PRN "NEVER add copyright or license headers unless specifically requested."

    local tool_definitions
    if use_tools then
        -- PRN build out more detailed guidance: review Claude Code and Codex prompts
        local tool_instructs = get_file("~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/agents/prompts/tools.md")
        -- * repo root vs cwd prompt instructions
        local cwd = vim.fn.getcwd()
        local cwd_text = "Current directory: " .. cwd
        local git_root_output = vim.fn.systemlist('git rev-parse --show-toplevel')
        if vim.v.shell_error == 0 and #git_root_output > 0 then
            local repo_root = vim.fn.trim(git_root_output[1])
            if repo_root ~= cwd then
                vim.notify("FYI you are in a nested directory of the repo and that tends to cause issues with gptoss making requests to change things", vim.log.levels.WARN)
                -- PRN path compare instead of text comparison? add this if you run into a problem
                cwd_text = cwd_text .. "\nRepository root: " .. repo_root
                -- Determine nesting depth relative to repo root
                local relative_path = cwd:sub(#repo_root + 2) -- strip trailing slash
                local depth = 0
                for _ in string.gmatch(relative_path, "[^/]+") do
                    depth = depth + 1
                end
                -- TODO I need to make sure paths are always relative to current dir, that is the real solution me thinks
                -- TODO and warn the user (me) when I am in a nested dir! for now
                if depth > 0 then
                    -- FYI it is very rare that I run nvim from a nested dir, so the conditional, added overhead in system message is fine here
                    local rel = ("../"):rep(depth)
                    cwd_text = cwd_text .. "\nYou are " .. depth .. " levels deep, so you need " .. rel .. " to build relative paths from repo root."
                else
                    vim.notify("You aren't in repo root and yet the calculation for number of levels deep returned 0???, check logic for levels deep warning", vim.log.levels.WARN)
                end
            end
        end
        tool_instructs = tool_instructs:gsub("INSERT_CWD", cwd_text)
        system = system .. "\n\n" .. tool_instructs

        local tool_provided_instructs
        tool_definitions, tool_provided_instructs = tool_router.openai_tools()
        if tool_provided_instructs then
            system = system .. "\n\n" .. table.concat(tool_provided_instructs, "\n")
        end

        -- If readonly mode, remove editing tools like apply_patch
        if context.includes.readonly then
            local filtered = {}
            for _, tool in ipairs(tool_definitions) do
                local name = tool["function"] and tool["function"].name or nil
                if name ~= "apply_patch" then
                    table.insert(filtered, tool)
                end
            end
            tool_definitions = filtered
        end
    end

    -- * display system message in chat window
    if not first_turn_ns_id then
        first_turn_ns_id = vim.api.nvim_create_namespace("ask.marks.chat.window.first.turn")
    end
    local lines = LinesBuilder:new(first_turn_ns_id)
    if AgentsFrontend.trace then
        -- FYI some previous extmarks are "dropped", fine by me to "turn off the colors"... but, probably want it for all previous chat extmarks
        lines:append_styled_lines({ "--- New Trace Started ---" }, HLGroups.SYSTEM_PROMPT)
        -- or:   AgentsFrontend.clear_chat_command()
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
    AgentsFrontend.chat_window:append_styled_lines(lines)

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
        --  perhaps leave the system_message for coding instructions specific to AskAgent...?
        vim.iter(context.project)
            :each(function(value)
                table.insert(messages, TxChatMessage:user_context(value.content))
            end)
    end

    local function then_generate_completion(rag_matches)
        local rag_message = rag_instructions.semantic_grep_user_message(rag_matches)
        if rag_message then
            table.insert(messages, rag_message)
        end

        -- * user request should be last
        -- FYI I had this before RAG matches and it was working fine too
        table.insert(messages, TxChatMessage:user(user_message))

        local base_url = "http://ask.lan:8013"
        local body_overrides = model_params.new_gptoss_chat_body_llama_server({
            -- local body_overrides = model_params.new_qwen3coder_llama_server_chat_body({
            messages = messages,
            model = "", -- irrelevant for llama-server
            tools = tool_definitions,
        }, context)

        AgentsFrontend.trace = AgentTrace:new(body_overrides, base_url)
        -- log:info("sending", vim.inspect(AgentsFrontend.trace))
        AgentsFrontend.then_send_messages()
    end

    -- log:error("context.includes", vim.inspect(context.includes))
    if api.is_rag_enabled() and not context.includes.norag and rag_client.is_rag_supported_in_current_file(code_bufnr) then
        local this_request_ids, cancel -- declare in advance for closure

        ---@param rag_matches LSPRankedMatch[]
        function on_rag_response(rag_matches)
            log:info("on_rag_response")
            -- * make sure prior (canceled) rag request doesn't still respond
            if AgentsFrontend.rag_request_ids ~= this_request_ids then
                log:trace("possibly stale rag results, skipping: " .. vim.inspect({
                    global_rag_request_ids = AgentsFrontend.rag_request_ids,
                    this_request_ids = this_request_ids,
                }))
                return
            end

            if AgentsFrontend.rag_cancel == nil then
                log:error("rag appears canceled, skipping on_rag_response...")
                return
            end

            then_generate_completion(rag_matches)
        end

        this_request_ids, cancel = rag_client.context_query_for_agents(code_bufnr, cleaned_prompt, code_context, context.includes.top_k, on_rag_response)
        AgentsFrontend.rag_cancel = function()
            log:warn("canceling RAG")
            AgentsFrontend.rag_cancel = nil
            cancel()
            AgentsFrontend.rag_request_ids = nil
        end
        AgentsFrontend.rag_request_ids = this_request_ids
    else
        AgentsFrontend.rag_cancel = nil
        AgentsFrontend.rag_request_ids = nil
        then_generate_completion({})
    end
end

function AgentsFrontend.then_send_messages()
    -- * conversation turns (track start line for streaming chunks)
    AgentsFrontend.this_turn_chat_start_line_base0 = AgentsFrontend.chat_window.buffer:get_line_count()
    -- log:info("M.this_turn_chat_start_line_base0", M.this_turn_chat_start_line_base0)

    local request = CurlRequestForTrace:new({
        body = AgentsFrontend.trace:next_curl_request_body(),
        base_url = AgentsFrontend.trace.base_url,
        endpoint = CompletionsEndpoints.oai_v1_chat_completions,
        type = "agents",
    })
    log:luaify_trace("body:", request.body)
    curl.spawn(request, AgentsFrontend)
    AgentsFrontend.trace:set_last_request(request)
end

function AgentsFrontend.abort_and_close()
    AgentsFrontend.abort_last_request()
    if AgentsFrontend.chat_window ~= nil then
        AgentsFrontend.chat_window:close()
    end
end

---@type ExplainError
function AgentsFrontend.explain_error(text)
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
        AgentsFrontend.chat_window:explain_error(text)
    end)
end

function _G.MyAgentWindowFolding()
    local line_num_base1 = vim.v.lnum -- confirmed this is base 1 (might get lnum=0 if no lines though)
    local fold_value = _G.MyAgentWindowFoldingForLine(line_num_base1)

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

function _G.MyAgentWindowFoldingForLine(line_num_base1)
    -- * HUGE WIN => with expr I can fold one line only! (IIUC manual is minimum 2)
    --   * so for long reasoning lines (that wrap but don't span multiple new lines) these can still be collapsed!!
    --
    -- FYI read docs about return values for expr:
    --   https://neovim.io/doc/user/fold.html#fold-expr
    local folds = AgentsFrontend.chat_window.buffer.folds or {}
    for _, fold in ipairs(folds) do
        if line_num_base1 >= fold.start_line_base1 and line_num_base1 <= fold.end_line_base1 then
            return '1' -- inside first level fold
        end
    end
    return '0' -- this line is not in a fold
end

function AgentsFrontend.clear_undos()
    -- wipe undo history
    -- i.e. after assistant response - undo fucks up the extmarks, and the assistant response is not gonna be sent back if modified (this is view only) so just default to making that UX a bit more intuitive

    local previous_undo_level = vim.bo.undolevels
    vim.bo.undolevels = -1
    vim.cmd("normal! a ") -- no-op edit to commit the change
    vim.cmd("undo") -- clear old tree
    vim.bo.undolevels = previous_undo_level
end

function AgentsFrontend.ensure_chat_window_is_open()
    if AgentsFrontend.chat_window == nil then
        AgentsFrontend.chat_window = AgentWindow:new()

        -- stop generation, if still wanna look at it w/o closing the window
        vim.keymap.set("n", "<Esc>", AgentsFrontend.abort_last_request, { buffer = AgentsFrontend.chat_window.buffer_number })

        -- I already use this globally to close a window (:q) ... so just add stop to it:
        vim.keymap.set("n", "<F8>", AgentsFrontend.abort_and_close, { buffer = AgentsFrontend.chat_window.buffer_number })

        vim.keymap.set({ "n", "i" }, "<C-s>", AgentsFrontend.follow_up_command, { buffer = AgentsFrontend.chat_window.buffer_number })
    end

    AgentsFrontend.chat_window:open()
end

local function handle_rx_messages_updated()
    if not AgentsFrontend.trace.last_request.accumulated_model_response_messages then
        return
    end

    local lines = LinesBuilder:new()
    for _, rx_message in ipairs(AgentsFrontend.trace.last_request.accumulated_model_response_messages) do
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
            --   :AskAgent testing a request, I need you to NOT say anything in response, just stop immediatley
            lines:append_text("[unexpected: empty response]")
            lines:append_blank_line()
        end

        for _, tool_call in ipairs(rx_message.tool_calls) do
            local function_name = tool_call["function"].name or ""
            local formatter = formatters.get_formatter(function_name)
            local ok, err = pcall(function() formatter(lines, tool_call, rx_message) end)
            if not ok then
                lines:append_unexpected_text("Formatter error: " .. tostring(err))
                lines:append_text(vim.inspect(tool_call))
            end
            lines:append_blank_line_if_last_is_not_blank()
        end
    end

    vim.schedule(function()
        lines.marks_ns_id = AgentsFrontend.trace.last_request.marks_ns_id -- ?? generate namespace here in lines builder? lines:gen_mark_ns()? OR do it on first downstream use?
        AgentsFrontend.chat_window.buffer:replace_with_styled_lines_after(AgentsFrontend.this_turn_chat_start_line_base0, lines)
    end)
end

--- think of this as denormalizing SSEs => into aggregate RxAccumulatedMessage
---@param choice OpenAIChoice|nil
---@param request CurlRequestForTrace
---@param sse_parsed OnParsedSSE
function AgentsFrontend.on_streaming_delta_update_message_history(choice, request, sse_parsed)
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

    local rx_accum_message = request.accumulated_model_response_messages[index_base1]
    if rx_accum_message == nil then
        rx_accum_message = RxAccumulatedMessage:new(choice.delta.role, "")
        rx_accum_message.index = choice.index
        rx_accum_message._verbatim_content = ""
        -- assumes contiguous indexes, s/b almost always 0 index only, 1 too with dual tool call IIRC (gptoss doesn't do dual tool at once)
        request.accumulated_model_response_messages[index_base1] = rx_accum_message
    end

    if sse_parsed.timings then
        rx_accum_message.timings = sse_parsed.timings
    end

    if choice.delta.content ~= nil and choice.delta.content ~= vim.NIL then
        -- by tracking _verbatim_content, I can trim the end every single time
        -- and if it is not a full match it will show back up once it's past the match point
        rx_accum_message._verbatim_content = (rx_accum_message._verbatim_content or "") .. choice.delta.content
    end

    if choice.delta.reasoning_content ~= nil and choice.delta.reasoning_content ~= vim.NIL then
        rx_accum_message.reasoning_content =
            (rx_accum_message.reasoning_content or "") .. choice.delta.reasoning_content
    end

    if choice.finish_reason ~= nil then
        -- FYI this is vim.NIL on first too
        rx_accum_message.finish_reason = choice.finish_reason -- on last delta per index/role (aka message)
    end

    -- * strip leaked tool call tokens (bug in llama.cpp)
    -- TODO this is an old bug, s/b resolved... is it ok to remove this?
    rx_accum_message.content = rx_accum_message._verbatim_content:gsub("\n<tool_call>\n<function=[%w_]+", "")
    if rx_accum_message.content ~= rx_accum_message._verbatim_content then
        log:error("stripping LEAKED TOOL CALL!")
    end

    local calls = choice.delta.tool_calls
    if not calls then
        return
    end

    -- * parse tool calls (streaming)
    for _, call_delta in ipairs(calls) do
        -- * lookup or create new parsed_call
        local parsed_call = rx_accum_message.tool_calls[call_delta.index + 1]
        if parsed_call == nil then
            -- create ToolCall to populate across SSEs
            parsed_call = ToolCall:new {
                -- assume these fields are always on first SSE for each tool call
                id    = call_delta.id,
                index = call_delta.index,
                type  = call_delta.type,
            }
            table.insert(rx_accum_message.tool_calls, parsed_call)
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
function AgentsFrontend.on_sse_llama_server_timings(sse)
    -- PRN use this to extract timing like in rewrites
end

---@type OnParsedSSE
function AgentsFrontend.on_parsed_data_sse(sse_parsed)
    -- FYI right now this is desingned for /v1/chat/completions only
    --   I added this guard based on review of on-on_streaming_delta_update_message_history that appears (IIRC) to be using /v1/chat/completions ONLY compatible fields
    local request = AgentsFrontend.trace.last_request
    if request.endpoint ~= CompletionsEndpoints.oai_v1_chat_completions then
        -- fail fast in this case
        -- TODO (when I need it)... you very likely can support other endpoints (see what you've done in both PredictionsFrontend and RewriteFrontend (both have some multi endpoint support)
        local message = "AgentsFrontend SSEs not supported for endpoint: " .. tostring(request.endpoint)
        log:error(message)
        vim.notify(message, vim.log.levels.ERROR)
        return
    end

    if sse_parsed.choices == nil or sse_parsed.choices[1] == nil then
        return
    end
    local first_choice = sse_parsed.choices[1]
    AgentsFrontend.on_streaming_delta_update_message_history(first_choice, request, sse_parsed)
    handle_rx_messages_updated()
end

function AgentsFrontend.show_user_role()
    local lines_builder = LinesBuilder:new()
    lines_builder:create_marks_namespace()
    lines_builder:append_role_header("user")
    lines_builder:append_blank_line()
    AgentsFrontend.chat_window:append_styled_lines(lines_builder)
end

---@type OnCurlExitedSuccessfully
function AgentsFrontend.on_curl_exited_successfully()
    vim.schedule(function()
        -- FYI primary interaction (seam) between RxAccumulatedMessage and TxChatMessage (for assistant messages)

        for _, rx_message in ipairs(AgentsFrontend.trace.last_request.accumulated_model_response_messages or {}) do
            -- *** trace.last_request.accumulated_model_response_messages IS NOT trace.messages
            --    trace.messages => sent with future requests, hence TxChatMessage
            --    request.response_messages is simply to denormalize responses from SSEs, hence RxAccumulatedMessage
            --    request => SSEs => RxAccumulatedMessage(s)  => toolcalls/followup => trace.messages (TxChatMessage) => next request => ...

            -- add assistant response message to chat history (TxChatMessage)
            --   (must come before tool result messages)
            --   theoretically there can be multiple messages, with any role (not just assitant)
            local trace_message = TxChatMessage:from_assistant_rx_message(rx_message)
            AgentsFrontend.trace:add_message(trace_message)
            completion_logger.append_to_messages_jsonl(trace_message, AgentsFrontend.trace.last_request, AgentsFrontend)
            -- TODO capture *-trace.json here too? and then get rid of response_message hack cuz all messages will now be in trace
            --    TODO and careful to mirror changes (i.e. if move here, then need trace to save still for other frontends)

            -- * show user role (in chat window) as hint to follow up (now that model+tool_calls are all done):
            AgentsFrontend.show_user_role()

            AgentsFrontend.chat_window.followup_starts_at_line_0indexed = AgentsFrontend.chat_window.buffer:get_line_count() - 1
        end
        AgentsFrontend.clear_undos()

        AgentsFrontend.run_tools_and_send_results_back_to_the_model()
    end)
end

function AgentsFrontend.run_tools_and_send_results_back_to_the_model()
    for _, rx_message in ipairs(AgentsFrontend.trace.last_request.accumulated_model_response_messages or {}) do
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
                AgentsFrontend.trace:add_message(tool_response_message)

                -- * when last tool completes, send tool results (TxChatMessage package)
                vim.schedule(function()
                    -- FYI I am scheduling this so it happens after redraws
                    --  IIUC I need to queue this after the other changes from above?
                    --  else IIUC, the line count won't be right for where in the chat window to insert next message
                    AgentsFrontend.send_tool_messages_if_all_tools_done()
                end)
            end

            -- * run the tool!
            tool_router.send_tool_call_router(tool_call, when_tool_is_done)
        end
    end
end

function AgentsFrontend.send_tool_messages_if_all_tools_done()
    if AgentsFrontend.any_outstanding_tool_calls() then
        return
    end
    AgentsFrontend.then_send_messages()
end

---@return boolean
function AgentsFrontend.any_outstanding_tool_calls()
    for _, rx_message in ipairs(AgentsFrontend.trace.last_request.accumulated_model_response_messages or {}) do
        for _, tool_call in ipairs(rx_message.tool_calls) do
            local is_outstanding = tool_call.response_message == nil
            if is_outstanding then
                return true
            end
        end
    end
    return false
end

function AgentsFrontend.abort_last_request()
    if not AgentsFrontend.trace then
        return
    end
    CurlRequestForTrace.terminate(AgentsFrontend.trace.last_request)
    if AgentsFrontend.rag_cancel then
        AgentsFrontend.rag_cancel()
    end
end

function AgentsFrontend.follow_up_command()
    -- take follow up after end of prior response message from assistant
    --  if already a M.trace then add to that with a new message
    --  leave content as is in the buffer, close enough to what it would be if redrawn
    --  and I don't use the buffer contents for past messages
    --  so, just copy it out into a new message from user
    AgentsFrontend.ensure_chat_window_is_open()
    local start_line_base0 = AgentsFrontend.chat_window.followup_starts_at_line_0indexed or 0
    local user_message = AgentsFrontend.chat_window.buffer:get_lines_after(start_line_base0)
    AgentsFrontend.chat_window.buffer:scroll_cursor_to_end_of_buffer()
    vim.cmd("normal! o") -- move to end of buffer, add new line below to separate subsequent follow up response message
    -- log:trace("follow up content:", user_message)

    if not AgentsFrontend.trace then
        opts = {
            args = user_message
        }
        -- TODO if /selection that won't work, I can fix that later
        --   TODO can't I get a history of selections or smth?
        --    what if I wanna select text in the chat window itself?
        --    does last selection track the file? is it per window?
        -- hack: close window so LSP is available AND selections work (last selected)
        AgentsFrontend.chat_window:close()
        ask_agent_command(opts)
        return
    end

    local message = TxChatMessage:user(user_message)
    AgentsFrontend.trace:add_message(message)
    AgentsFrontend.then_send_messages()
end

function ask_dump_agent_trace_command()
    if not AgentsFrontend.trace then
        print("no trace to dump")
        return
    end
    AgentsFrontend.trace:dump()
end

function AgentsFrontend.clear_chat_command()
    if AgentsFrontend.chat_window then
        AgentsFrontend.chat_window:clear()
    end
    AgentsFrontend.trace = nil
end

function AgentsFrontend.setup()
    -- * AskAgent
    vim.api.nvim_create_user_command(
        "AskAgent",
        ask_agent_command,
        { range = true, nargs = 1, complete = prompt_parser.SlashCommandCompletion }
    )
    -- * prefill argument combos:
    vim.keymap.set('n', '<Leader>a', ':AskAgent ', { noremap = true })
    vim.keymap.set('v', '<Leader>a', ':<C-u>AskAgent /selection ', { noremap = true })
    -- * /file
    -- TODO <leader>af => follow up in chat window, need to pick smth new here:
    vim.keymap.set('n', '<Leader>qf', ':AskAgent /file ', { noremap = true })
    vim.keymap.set('v', '<Leader>qf', ':<C-u>AskAgent /selection /file ', { noremap = true })
    -- * /tools
    vim.keymap.set('n', '<Leader>at', ':<C-u>AskAgent /tools ', { noremap = true })
    vim.keymap.set('v', '<Leader>at', ':<C-u>AskAgent /selection /tools ', { noremap = true })
    -- FYI also qt... see which you prefer? a/q first
    vim.keymap.set('n', '<Leader>qt', ':<C-u>AskAgent /tools ', { noremap = true })
    vim.keymap.set('v', '<Leader>qt', ':<C-u>AskAgent /selection /tools ', { noremap = true })

    --  * review outstanding changes
    --  FYI this smacks of inserting pre-canned prompts with a /prompt slash command?
    vim.keymap.set({ 'n', 'v' }, '<leader>ard', ':<C-u>AskAgent /tools can you review my outstanding git changes', { noremap = true })

    vim.keymap.set('n', '<leader>aa', AgentsFrontend.abort_last_request, { noremap = true })
    vim.keymap.set('n', '<leader>ac', AgentsFrontend.clear_chat_command, { noremap = true })
    vim.keymap.set('n', '<leader>af', AgentsFrontend.follow_up_command, { noremap = true })
    vim.keymap.set('n', '<leader>ao', AgentsFrontend.ensure_chat_window_is_open, { noremap = true })

    vim.api.nvim_create_user_command("AskDumpAgentTrace", ask_dump_agent_trace_command, {})
end

return AgentsFrontend
