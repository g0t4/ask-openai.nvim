local buffers = require("ask-openai.helpers.buffers")
local local_share = require("ask-openai.config.local_share")
local models = require("ask-openai.config.models")
local log = require("devtools.logs.logger").universal()
local completion_logger = require("ask-openai.logs.completion_logger")
local tool_router = require("ask-openai.tools.router")
local curl = require("ask-openai.backends.curl")
local AgentWindow = require("ask-openai.agents.viewer.window")
local UserInputWindow = require("ask-openai.agents.viewer.user_input_window")
local AgentTrace = require("ask-openai.agents.trace")
local TracePager = require("ask-openai.agents.viewer.trace_pager")
local LlamaServerClient = require("ask-openai.backends.llama_cpp.llama_server_client")
local notify = require("devtools.notify")
local TxChatMessage = require("ask-openai.agents.messages.tx")
local Selection = require("ask-openai.helpers.selection")
local CurrentContext = require("ask-openai.frontends.context")
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
local config = require("ask-openai.config")
local context_builder = require("ask-openai.agents.context_builder")
local trace_restorer = require("ask-openai.agents.viewer.trace_restorer")

require("ask-openai.helpers.buffers")

---@class AgentsFrontend : StreamingFrontend
local AgentsFrontend = {}

---@type string[] -- user messages typed into the input box while the agent is running (awaiting delivery)
AgentsFrontend.queued_user_messages = {}
---@type number|nil -- 0-indexed line where the rendered queued-messages section begins in the chat window
AgentsFrontend.queued_section_start_line_base0 = nil
---@type UserInputWindow|nil
AgentsFrontend.user_input_window = nil
---@type boolean -- true while a request was aborted; prevents a finishing tool call from resuming the agent
AgentsFrontend.request_aborted = false

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

    AgentsFrontend.abort_request()
    use_tools = context.includes.use_tools or false

    local system = get_file("~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/agents/prompts/system_message.md")
    -- PRN "NEVER add copyright or license headers unless specifically requested."

    local tool_definitions
    if use_tools then
        -- PRN build out more detailed guidance: review Claude Code and Codex prompts
        local tool_instructs = get_file("~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/agents/prompts/tools.md")
        -- * repo root vs cwd prompt instructions
        local cwd = vim.fn.getcwd()
        local repo_root = files.get_repo_root()
        local cwd_text = context_builder.build_git_context(cwd, repo_root)

        system = system:gsub("INSERT_CWD", cwd_text)

        system = system .. "\n\n" .. tool_instructs



        local tool_provided_instructs
        -- Pass coordinator flag based on slash command "coordinator"
        local coordinator_flag = context.includes.coordinator or false
        tool_definitions, tool_provided_instructs = tool_router.openai_tools(coordinator_flag)
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
    else
        system = system:gsub("INSERT_CWD", "")
    end

    -- * display system message in chat window
    if not first_turn_ns_id then
        first_turn_ns_id = vim.api.nvim_create_namespace("ask.marks.chat.window.first.turn")
    end
    local lines = LinesBuilder:new(first_turn_ns_id)
    local is_new_trace = AgentsFrontend.trace ~= nil
    if is_new_trace then
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

    local function then_add_seed_user_messages(rag_matches)
        local rag_message = rag_instructions.semantic_grep_user_message(rag_matches)
        if rag_message then
            table.insert(messages, rag_message)
        end

        -- FYI user request works well regardless if it is first or last user message
        table.insert(messages, TxChatMessage:user(user_message))

        local generic_body = {
            messages = messages,
            model = "", -- irrelevant for llama-server
            tools = tool_definitions,
            verbose = true, -- capture __verbose one-off
        }

        local model = config.get_agents_model()
        local reasoning_level = context.includes:get_reasoning_level() or config.get_agents_reasoning_level()

        local base_url = config.get_base_url(model)
        local new_trace = AgentTrace:new(model_params.body_for(model, generic_body, reasoning_level), base_url)
        AgentsFrontend.trace = new_trace -- FYI `.trace` is intended for rare circumstances only, i.e. cancel action which has no context to pass a trace
        -- log:info("sending", vim.inspect(AgentsFrontend.trace))
        AgentsFrontend.then_get_assistant_response(new_trace)
    end

    -- log:error("context.includes", vim.inspect(context.includes))
    if config.is_rag_enabled() and not context.includes.norag and rag_client.is_rag_supported_in_current_file(code_bufnr) then
        local this_request_ids, cancel -- declare in advance for closure

        ---@param obj SemanticGrepWithTimeoutResponseObj -- for lack of better name, stick with it
        function on_rag_response(obj)
            -- * make sure prior (canceled) rag request doesn't still respond
            if AgentsFrontend.rag_request_ids ~= this_request_ids then
                log:trace("possibly stale rag results, skipping: " .. vim.inspect({
                    global_rag_request_ids = AgentsFrontend.rag_request_ids,
                    this_request_ids = this_request_ids,
                }))
                return
            end
            -- ** DO NOT LOOK AT A RESPONSE (neither isError nor matches) IF IT IS NOT FOR THE LATEST REQUEST!

            if obj.result.isError then
                log:error("RAG failed in AgentsFrontend")
                vim.notify("RAG failed in AgentsFrontend, skipping RAG " .. vim.inspect(obj))
            end

            if AgentsFrontend.rag_cancel == nil then
                log:error("rag appears canceled, skipping on_rag_response...")
                return
            end

            then_add_seed_user_messages(obj.result.matches or {})
        end

        this_request_ids, cancel = rag_client.context_query_for_agents(code_bufnr, cleaned_prompt, code_context, nil, on_rag_response)
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
        then_add_seed_user_messages({})
    end
end

---@param trace AgentTrace
function AgentsFrontend.then_get_assistant_response(trace)
    -- * a new request is starting, clear any prior abort state
    AgentsFrontend.request_aborted = false

    -- * conversation turns (track start line for streaming chunks)

    AgentsFrontend.this_turn_chat_start_line_base0 = AgentsFrontend.chat_window.buffer:get_line_count()
    -- log:info("M.this_turn_chat_start_line_base0", M.this_turn_chat_start_line_base0)
    AgentsFrontend.chat_window:mark_agent_running(true)
    AgentsFrontend.chat_window:ensure_spinner_running("agenting...")

    -- * make the dedicated input box available so the user can type while the agent works
    AgentsFrontend.ensure_user_input_window_is_open()

    local next_request = CurlRequestForTrace:new({
        body = trace:next_curl_request_body(),
        base_url = trace.base_url,
        endpoint = CompletionsEndpoints.v1_chat_completions,
        type = "agents",
    })
    log:luaify_trace("body:", next_request.body)
    curl.spawn(next_request, AgentsFrontend)
    trace:set_last_request(next_request)
end

function AgentsFrontend.abort_and_close()
    AgentsFrontend.abort_request()
    if AgentsFrontend.chat_window ~= nil then
        AgentsFrontend.chat_window:close()
    end
    if AgentsFrontend.user_input_window ~= nil then
        AgentsFrontend.user_input_window:hide()
    end
end

function AgentsFrontend.save_current_user_message()
    local start_line_base0 = AgentsFrontend.chat_window.followup_starts_at_line_0indexed or 0
    local user_message = AgentsFrontend.chat_window.buffer:get_lines_from(start_line_base0)

    -- * save it to a file in SHADA DIR for recovery
    local api = require('non-plugins.werkspaces.api')
    local state_dir = api.get_werkspace_state_dir()
    if not user_message then
        error("NO USER MESSAGE, aborting save...")
    end

    local file_path = state_dir .. "/last-user-message.txt"
    local file = io.open(file_path, "w")
    if file then
        file:write(user_message)
        file:close()
    end
    print("saved to " .. file_path)
end

function AgentsFrontend.load_last_user_message()
    -- TODO open chat if not already
    AgentsFrontend.ensure_chat_window_is_open()

    local api = require('non-plugins.werkspaces.api')
    local state_dir = api.get_werkspace_state_dir()
    local file_path = state_dir .. "/last-user-message.txt"
    local file = io.open(file_path, "r")
    if not file then
        error("no user message found, aborting restore... " .. file_path)
    end
    local user_message_lines = vim.split(file:read("*a"), "\n")
    table.insert(user_message_lines, "") -- add blank line after so cursor feels right (moves to end which s/b blank line) - remove this if I hate it later
    file:close()
    -- FYI when we move to split user message input, can just load into that dedicated user message floating window
    -- insert at end of buffer as the user's message
    vim.api.nvim_buf_set_lines(AgentsFrontend.chat_window.buffer.buffer_number, -1, -1, false, user_message_lines)
    -- move cursor to end
    AgentsFrontend.chat_window.buffer:scroll_cursor_to_end_of_buffer()
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
    -- wipe undo history on the CHAT buffer only.
    -- i.e. after assistant response - undo fucks up the extmarks, and the assistant response is not gonna be sent back if modified (this is view only) so just default to making that UX a bit more intuitive
    -- NOTE: must operate ONLY on the chat buffer. The old `vim.cmd("normal! a ")` ran on
    -- whatever buffer is *current* (e.g. the user input box while the agent works), inserting
    -- a stray space and shoving the user's cursor right by one on every tool call.

    -- TODO remove this when we move to a read only history window
    local buffer = AgentsFrontend.chat_window and AgentsFrontend.chat_window.buffer
    if not buffer then
        return
    end

    local bufnr = buffer.buffer_number
    local previous_undo_level = vim.bo[bufnr].undolevels

    vim.bo[bufnr].undolevels = -1

    -- Rewrite one line to clear the undo tree without moving any cursor.
    local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, first_line)

    vim.bo[bufnr].undolevels = previous_undo_level
    local buffer = AgentsFrontend.chat_window and AgentsFrontend.chat_window.buffer
end

function AgentsFrontend.ensure_chat_window_is_open()
    if AgentsFrontend.chat_window == nil then
        local window = AgentWindow:new()
        AgentsFrontend.chat_window = window

        -- * lookup model name (to show in title)
        local configured_model = config.get_agents_model()
        local base_url = config.get_base_url(configured_model)
        config.get_llama_server_model_info(base_url, function(model)
            AgentsFrontend.chat_window:update_model_name(model.name)
        end)

        -- stop generation, if still wanna look at it w/o closing the window
        vim.keymap.set("n", "<Esc>", AgentsFrontend.abort_request, { buffer = AgentsFrontend.chat_window.buffer_number })

        -- I already use this globally to close a window (:q) ... so just add stop to it:
        vim.keymap.set("n", "<F8>", AgentsFrontend.abort_and_close, { buffer = AgentsFrontend.chat_window.buffer_number })

        vim.keymap.set({ "n", "i" }, "<C-s>", AgentsFrontend.save_current_user_message, { buffer = AgentsFrontend.chat_window.buffer_number })
    end

    AgentsFrontend.chat_window:open()
end

---@param trace AgentTrace
local function update_ui_chat_viewer(trace)
    local request = trace.last_request

    local lines = LinesBuilder:new()
    for _, rx_message in ipairs(request.accumulated_model_response_messages or {}) do
        -- FYI !! now it is obvious that this is only operating on accumulated message type!

        -- * message contents
        local content = rx_message.content or ""
        local reasoning_content = rx_message.reasoning_content or ""

        if content ~= "" or reasoning_content ~= "" then
            -- ONLY add role header IF there is content (or reasoning) to show... otherwise just show tool_call(s)
            lines:append_role_header(rx_message.role)

            lines:append_folded_styled_text(reasoning_content, HLGroups.CHAT_REASONING)

            lines:append_text(content)
            -- Show per-message timings for assistant once complete
            if rx_message.role == 'assistant' and rx_message.last_sse and rx_message.last_sse.timings then
                local t = rx_message.last_sse.timings
                local parts = {}

                if t.cache_n and t.cache_n > 0 then
                    table.insert(parts, string.format('%d cached', t.cache_n))
                end

                local input = string.format('in: %d', t.prompt_n or 0)
                if t.prompt_per_second and t.prompt_per_second > 0 then
                    input = input .. string.format(' @ %.0f tok/s', t.prompt_per_second)
                end
                table.insert(parts, input)

                local output = string.format('out: %d', t.predicted_n or 0)
                if t.predicted_per_second and t.predicted_per_second > 0 then
                    output = output .. string.format(' @ %.0f tok/s', t.predicted_per_second)
                end
                table.insert(parts, output)

                -- draft token stats
                if t.draft_n then
                    local draft = string.format('draft: %d', t.draft_n_accepted)
                    if t.draft_n_accepted then
                        local percent = t.draft_n_accepted / t.draft_n * 100
                        draft = draft .. string.format(' @ %.0f%%', percent)
                    end
                    table.insert(parts, draft)
                end

                if #parts > 0 then
                    lines:append_styled_text(table.concat(parts, ' | '), HLGroups.CHAT_REASONING)
                end
            end
            lines:append_blank_line_if_last_is_not_blank() -- only if reasoning doesn't have trailing \n
        elseif #rx_message.tool_calls == 0 then
            -- gptoss120b - this works:
            --   :AskAgent testing a request, I need you to NOT say anything in response, just stop immediatley
            lines:append_text("[unexpected: empty response]")
            lines:append_blank_line()
        end

        for _, tool_call in ipairs(rx_message.tool_calls) do
            local function_name = tool_call["function"] and tool_call["function"].name or ""
            local formatter = formatters.get_formatter(function_name)
            local ok, err = pcall(function() formatter(lines, tool_call, rx_message) end)
            if not ok then
                lines:append_unexpected_text("Formatter error: " .. tostring(err))
                lines:append_text(vim.inspect(tool_call))
            end
            lines:append_blank_line_if_last_is_not_blank()
        end
    end

    local function _comma_separate(n)
        local s = tostring(n)
        local result = ""
        local count = 0
        for i = #s, 1, -1 do
            count = count + 1
            result = s:sub(i, i) .. result
            if count % 3 == 0 and i > 1 then
                result = "," .. result
            end
        end
        return result
    end

    vim.schedule(function()
        lines.marks_ns_id = request.marks_ns_id -- ?? generate namespace here in lines builder? lines:gen_mark_ns()? OR do it on first downstream use?
        AgentsFrontend.chat_window.buffer:replace_with_styled_lines_after(AgentsFrontend.this_turn_chat_start_line_base0, lines)

        -- * re-pin any queued user messages to the bottom (the replace wiped the prior queued section)
        AgentsFrontend.queued_section_start_line_base0 = nil
        AgentsFrontend.redraw_queued_user_messages()

        -- * update window title with model name and token count
        local last_message = request.accumulated_model_response_messages[#request.accumulated_model_response_messages]
        if last_message and last_message.last_sse then
            -- log:info("last_message", last_message)
            local last_sse = last_message.last_sse
            local timings = last_sse.timings
            local footers = {}
            if last_sse.model then
                table.insert(footers, last_sse.model)
            end
            if timings then
                local cache_token_count = timings.cache_n or 0
                local prompt_token_count = timings.prompt_n or 0
                local predicted_token_count = timings.predicted_n or 0
                local total_token_count = cache_token_count + prompt_token_count + predicted_token_count
                local token_footer = "tokens: " .. _comma_separate(total_token_count)
                table.insert(footers, token_footer)
            end
            local footer = table.concat(footers, " | ")
            -- PRN? add AgentWindow:set_footer_parts() and have it call rebuild?
            AgentsFrontend.chat_window._footer = footer
            AgentsFrontend.chat_window:rebuild_title()
        end
    end)
end

--- think of this as denormalizing SSEs => into aggregate RxAccumulatedMessage
---@param choice OpenAIChoice|nil
---@param request CurlRequestForTrace
---@param sse_parsed LlamaServerSSEBase
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

    local is_last_sse = sse_parsed.timings
    if is_last_sse then
        rx_accum_message.last_sse = sse_parsed
        -- rx_accum_message.timings = sse_parsed.timings -- ? should I just copy this one part only and skip rest of last_sse?
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
    local trace = AgentsFrontend.trace
    local request = trace.last_request
    if request.endpoint ~= CompletionsEndpoints.v1_chat_completions then
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
    update_ui_chat_viewer(trace)
end

---@type OnCurlExitedSuccessfully
function AgentsFrontend.on_curl_exited_successfully()
    vim.schedule(function()
        -- FYI primary interaction (seam) between RxAccumulatedMessage and TxChatMessage (for assistant messages)
        local trace = AgentsFrontend.trace -- FYI could pass trace from backend that calls on_curl_exited_successfully()
        local request = trace.last_request

        -- * verify responding model matches configured model
        --  this way I can use configured in advance of first request, which is a reasonable assumption (i.e. to build model specific prompt) and then only warn here if there's an actual problem
        --  so I don't hold up every request to check this in advance
        --  PRN add parallel test of the name? send it with RAG request? else before?
        local last_message = request.accumulated_model_response_messages and request.accumulated_model_response_messages[#request.accumulated_model_response_messages]
        if last_message and last_message.last_sse and last_message.last_sse.model then
            local actual_name = last_message.last_sse.model
            local actual_abbrev = models.abbreviate_model(actual_name)
            -- map abstract configured model to expected abbrev
            local configured_model = config.get_agents_model()
            local configured_abbrev = models.abbreviate_model(configured_model)
            if actual_abbrev ~= configured_abbrev then
                vim.notify("Model mismatch: configured " .. configured_model .. " (" .. configured_abbrev .. ") vs actual " .. actual_name .. " (" .. actual_abbrev .. ")", vim.log.levels.WARN)
            end
        end

        local has_tool_calls = false
        local reached_final_message = false
        for _, rx_message in ipairs(request.accumulated_model_response_messages or {}) do
            -- *** trace.last_request.accumulated_model_response_messages IS NOT trace.messages
            --    trace.messages => sent with future requests, hence TxChatMessage
            --    request.response_messages is simply to denormalize responses from SSEs, hence RxAccumulatedMessage
            --    request => SSEs => RxAccumulatedMessage(s)  => toolcalls/followup => trace.messages (TxChatMessage) => next request => ...

            -- add assistant response message to chat history (TxChatMessage)
            --   (must come before tool result messages)
            --   theoretically there can be multiple messages, with any role (not just assitant)
            local trace_message = TxChatMessage:from_assistant_rx_message(rx_message)
            trace:add_message(trace_message)
            -- TODO could I merge this accum logic with completion logger's accum logic?
            -- right now I duplicate that logic here for AgentsFrontend
            -- but, that logic is only in completion_logger for other frontends (PredictionsFrontend/RewriteFrontend) that don't need to accum like with `AgentsFrontend`

            -- TODO strip prefill assistant messages from trace.messages so they don't remain
            --  they're just a mechanism to constrain the following agent response... need merged with the agent's response actually?
            --  at the same time I like the history of what was submitted
            --  this is the inherent tension between adding that assistant response message to the messages array (which is really for the next request)... vs keeping it separate as the completion to the messages array sent as-is to llama-server

            local is_final_assistant_message = #rx_message.tool_calls == 0
            if not is_final_assistant_message then
                has_tool_calls = true
            end
            if is_final_assistant_message then
                reached_final_message = true
                AgentsFrontend.chat_window:mark_agent_running(false)
                AgentsFrontend.chat_window:stop_spinner("Agent Finished")
            end
            -- set offset after every assistant message, that way if anything goes awry the user can resume by typing below the last assistant message (i.e. "resume") and trigger follow up (even if say tool call was in progress and blew up)
            AgentsFrontend.chat_window.followup_starts_at_line_0indexed = AgentsFrontend.chat_window.buffer:get_line_count() - 1
        end
        AgentsFrontend.clear_undos()

        -- * If the agent finished (final message) and the user queued messages while it ran,
        --   deliver them now as a normal follow-up instead of waiting for the next tool call.
        local should_deliver_queued_as_followup = reached_final_message and #AgentsFrontend.queued_user_messages > 0

        if should_deliver_queued_as_followup then
            local queued = AgentsFrontend.queued_user_messages
            AgentsFrontend.queued_user_messages = {}
            -- * drop the rendered queued section (submit_follow_up re-displays it as a normal user message)
            AgentsFrontend.redraw_queued_user_messages()
            AgentsFrontend.submit_follow_up(table.concat(queued, "\n"))
            return
        end

        AgentsFrontend.run_tools_and_send_results_back_to_the_model(trace)
    end)
end

---@param trace AgentTrace
function AgentsFrontend.run_tools_and_send_results_back_to_the_model(trace)
    local request = trace.last_request
    for _, rx_message in ipairs(request.accumulated_model_response_messages or {}) do
        for _, tool_call in ipairs(rx_message.tool_calls) do
            -- FYI primary interaction (seam) between RxAccumulatedMessage and TxChatMessage (for tool result messages)

            ---@type ToolCallDoneCallback
            local function when_this_tool_is_done(tool_call_output)
                -- * compute tool call duration
                local end_time_ms = math.floor(vim.uv.hrtime() / 1e6)
                local tool_call_duration_ms = end_time_ms - tool_call.start_time_ms

                -- * store output on rx_message with timing
                tool_call.call_output = ToolCallOutput:new(tool_call_output)
                tool_call.call_output.start_time_ms = tool_call.start_time_ms
                tool_call.call_output.duration_ms = tool_call_duration_ms
                log:trace("tool_call_output", vim.inspect(tool_call_output))

                -- * triggers UI updates to show tool results
                update_ui_chat_viewer(trace)

                -- * map tool result to a new TxChatMessage (to send back to model)
                local tool_response_message = TxChatMessage:tool_result(tool_call)
                -- log:jsonify_compact_trace("tool_message:", tool_response_message)
                tool_call.response_message = tool_response_message
                trace:add_message(tool_response_message)

                if request:any_outstanding_tool_calls() or request.already_sent then
                    return
                end

                -- * if the user aborted while the tool ran, do NOT resume the agent
                if AgentsFrontend.request_aborted then
                    log:warn("request aborted during tool call; not resuming the agent")
                    return
                end
                request.already_sent = true

                -- * deliver any queued user messages as an interruption before continuing
                AgentsFrontend.inject_queued_user_messages(trace)

                -- IIUC I need to queue this after the changes from update_chat_viewer_buffer?
                -- else IIRC, the line count will be broken for the next message
                vim.schedule(function() AgentsFrontend.then_get_assistant_response(trace) end)
            end

            local function on_tool_progress(progress)
                -- * extract message from MCP progress notification
                local progress_message = progress.message
                if not progress_message or progress_message:match("^%s*$") then
                    return
                end

                tool_call:add_progress_message(progress_message)

                update_ui_chat_viewer(trace)
            end

            -- * capture start time before running the tool
            tool_call.start_time_ms = math.floor(vim.uv.hrtime() / 1e6)

            -- * run the tool!
            tool_router.send_tool_call_router(tool_call, when_this_tool_is_done, on_tool_progress)
        end
    end
end

function AgentsFrontend.abort_request()
    -- * remember we aborted so a finishing tool call won't resume the agent
    AgentsFrontend.request_aborted = true

    -- * aborting discards any queued user messages
    if #AgentsFrontend.queued_user_messages > 0 then
        AgentsFrontend.queued_user_messages = {}
        AgentsFrontend.redraw_queued_user_messages()
    end

    local trace = AgentsFrontend.trace
    if not trace then
        return
    end
    CurlRequestForTrace.terminate(trace.last_request)
    if AgentsFrontend.chat_window._agent_is_running then
        -- TODO only "cancel" if agent is running? (i.e. why call rag_cancel (etc) if agent is done (or never started)
        AgentsFrontend.chat_window:mark_agent_running(false)
        AgentsFrontend.chat_window:stop_spinner("Aborted") -- FYI don't mark aborted if not running
    end
    if AgentsFrontend.rag_cancel then
        AgentsFrontend.rag_cancel()
    end
end

--- Interrupt the agent mid-completion: stop it (like cancel/escape), keep the partial
--- assistant response as context, and immediately deliver the queued user message(s) as an
--- interruption so the agent can butt in and respond without waiting for it to finish.
function AgentsFrontend.interrupt_agent()
    local is_running = AgentsFrontend.chat_window and AgentsFrontend.chat_window._agent_is_running

    -- * if the agent isn't running, just deliver any queued messages as a normal follow-up
    if not is_running then
        local queued_messages = AgentsFrontend.queued_user_messages
        AgentsFrontend.queued_user_messages = {}
        AgentsFrontend.redraw_queued_user_messages()
        if #queued_messages > 0 then
            AgentsFrontend.submit_follow_up(table.concat(queued_messages, "\n"))
        end
        return
    end

    local trace = AgentsFrontend.trace
    -- * capture the queued user messages (they are sent immediately, not deferred)
    local queued_messages = AgentsFrontend.queued_user_messages
    AgentsFrontend.queued_user_messages = {}

    -- * stop the agent like cancel/escape does
    AgentsFrontend.request_aborted = true
    if trace then
        CurlRequestForTrace.terminate(trace.last_request)
    end
    AgentsFrontend.chat_window:mark_agent_running(false)
    AgentsFrontend.chat_window:stop_spinner("Interrupted")
    if AgentsFrontend.rag_cancel then
        AgentsFrontend.rag_cancel()
    end

    -- * drop the rendered queued section (re-rendered as a normal user message below)
    AgentsFrontend.queued_section_start_line_base0 = nil
    AgentsFrontend.redraw_queued_user_messages()

    if not trace then
        return
    end

    -- * keep the partial agent response (reasoning/content/tool calls) so the model
    --   can continue from where it was cut off
    local request = trace.last_request
    if request and request.accumulated_model_response_messages then
        for _, rx_message in ipairs(request.accumulated_model_response_messages) do
            if rx_message.content and rx_message.content ~= "" then
                trace:add_message(TxChatMessage:from_assistant_rx_message(rx_message))
            end
        end
    end

    -- * tell the agent we interrupted its work and pass along the queued message(s)
    local interruption = TxChatMessage:user(build_interrupt_message(queued_messages))
    trace:add_message(interruption)

    -- * render the interruption message, then immediately ask the agent to continue
    display_user_message_in_chat(interruption.content)
    AgentsFrontend.then_get_assistant_response(trace)
end

--- Add a user message to the current trace and trigger the next agent response.
---@param user_message string
local function send_trace_follow_up(user_message)
    local trace = AgentsFrontend.trace
    local message = TxChatMessage:user(user_message)
    trace:add_message(message)
    AgentsFrontend.then_get_assistant_response(trace)
end

--- Build the interruption user message from one or more queued messages.
--- Instructs the agent to resume the prior request unless told otherwise.
---@param queued_messages string[]
---@return string
local function build_interruption_message(queued_messages)
    local parts = {
        "[Queued while you were completing the prior request]",
        "I wanted to add context while you were working. Please resume the prior request unless I instruct you to stop and/or change course.",
    }
    for index, message in ipairs(queued_messages) do
        if #queued_messages > 1 then
            table.insert(parts, string.format("-- queued message %d of %d --", index, #queued_messages))
        end
        table.insert(parts, message)
    end
    return table.concat(parts, "\n")
end

--- Build the interruption user message that explains the agent's work was cut short
--- to deliver one or more queued messages immediately (vs. waiting for completion).
---@param queued_messages string[]
---@return string
local function build_interrupt_message(queued_messages)
    local parts = {
        "[I interrupted your work before you finished]",
        "I stopped you mid-completion so I could tell you this. Keep the work you had done so far, incorporate what I am telling you now, and continue/resume your prior request unless I instruct you to stop and/or change course.",
    }
    for index, message in ipairs(queued_messages) do
        if #queued_messages > 1 then
            table.insert(parts, string.format("-- queued message %d of %d --", index, #queued_messages))
        end
        table.insert(parts, message)
    end
    return table.concat(parts, "\n")
end

--- Display a user message as a role-styled section at the end of the chat window.
---@param text string
local function display_user_message_in_chat(text)
    local lines = LinesBuilder:new()
    lines:create_marks_namespace()
    lines:append_role_header("user")
    lines:append_text(text)
    lines:append_blank_line()
    AgentsFrontend.chat_window:append_styled_lines(lines)
end

--- Re-render the queued user messages pinned to the bottom of the chat window.
--- Drops any previously-rendered queued section, then (re)appends the current queue.
function AgentsFrontend.redraw_queued_user_messages()
    if not AgentsFrontend.chat_window then
        return
    end
    local buffer = AgentsFrontend.chat_window.buffer
    local bufnr = buffer.buffer_number

    -- * drop any previously rendered queued section (a viewer update wiped it, marker is stale)
    if AgentsFrontend.queued_section_start_line_base0 then
        local start_line_base0 = AgentsFrontend.queued_section_start_line_base0
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        if start_line_base0 < line_count then
            vim.api.nvim_buf_set_lines(bufnr, start_line_base0, -1, false, {})
        end
        AgentsFrontend.queued_section_start_line_base0 = nil
    end

    if #AgentsFrontend.queued_user_messages == 0 then
        return
    end

    local lines = LinesBuilder:new()
    lines:create_marks_namespace()
    lines:append_role_header("user")
    for _, message in ipairs(AgentsFrontend.queued_user_messages) do
        lines:append_text(message)
    end
    lines:append_blank_line()

    local start_line_base0 = buffer:get_line_count()
    if start_line_base0 == 1 and buffer:get_lines_from(0) == "" then
        start_line_base0 = 0
    end
    AgentsFrontend.queued_section_start_line_base0 = start_line_base0
    buffer:append_styled_lines(lines)
end

--- Submit a user message. While the agent runs it is queued for later delivery;
--- otherwise it is submitted as a normal follow-up.
---@param user_message string
---@return "empty"|"queued"|"submitted"
function AgentsFrontend.submit_user_message(user_message)
    user_message = user_message:gsub("^%s+", ""):gsub("%s+$", "")
    if user_message == "" then
        return "empty"
    end

    if AgentsFrontend.chat_window and AgentsFrontend.chat_window._agent_is_running then
        table.insert(AgentsFrontend.queued_user_messages, user_message)
        AgentsFrontend.redraw_queued_user_messages()
        return "queued"
    end

    AgentsFrontend.submit_follow_up(user_message)
    return "submitted"
end

--- Submit a follow-up user message against the current trace (or start a new one).
---@param user_message string
function AgentsFrontend.submit_follow_up(user_message)
    AgentsFrontend.ensure_chat_window_is_open()

    local trace = AgentsFrontend.trace
    if not trace then
        -- * start a brand-new trace; ask_agent_command also displays the user message
        ask_agent_command({ args = user_message })
        return
    end

    -- * display the user message in the chat window, then send it
    display_user_message_in_chat(user_message)
    send_trace_follow_up(user_message)
end

--- Inject queued user messages into the trace as an interruption user message.
--- Called right before the next request is sent after a tool call completes.
---@param trace AgentTrace
function AgentsFrontend.inject_queued_user_messages(trace)
    if #AgentsFrontend.queued_user_messages == 0 then
        return
    end

    local interruption = TxChatMessage:user(build_interruption_message(AgentsFrontend.queued_user_messages))
    trace:add_message(interruption)

    -- * consumed: clear the queue (the rendered section stays in the buffer as history)
    AgentsFrontend.queued_user_messages = {}
    AgentsFrontend.queued_section_start_line_base0 = nil
end

--- Ensure the dedicated user message input box is open.
--- Focuses + starts insert mode on first creation (or when `focus` is truthy).
---@param focus? boolean
function AgentsFrontend.ensure_user_input_window_is_open(focus)
    local is_new = AgentsFrontend.user_input_window == nil
    if is_new then
        AgentsFrontend.user_input_window = UserInputWindow:new()

        local bufnr = AgentsFrontend.user_input_window.buffer_number

        -- * auto-resize as the prompt grows/shrinks (TextChangedI catches each
        --   keystroke; TextChanged catches pastes/undo) so a long prompt gets more
        --   room and the chat window shrinks to match
        vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
            buffer = bufnr,
            callback = function()
                if AgentsFrontend.user_input_window then AgentsFrontend.user_input_window:resize() end
                if AgentsFrontend.chat_window then AgentsFrontend.chat_window:resize() end
            end,
        })

        -- * submit on <CR> (insert & normal mode)
        vim.keymap.set({ "i", "n" }, "<CR>", function()
            AgentsFrontend.submit_from_input_window()
        end, { buffer = bufnr, desc = "submit the queued user message" })

        -- * Shift+Enter inserts a blank line (for multi-line messages) without submitting
        vim.keymap.set("i", "<S-CR>", function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
        end, { buffer = bufnr, desc = "insert a blank line in user message" })

        -- * hide the input box
        vim.keymap.set({ "i", "n" }, "<C-c>", function()
            AgentsFrontend.user_input_window:hide()
        end, { buffer = bufnr, desc = "close the user message input box" })
    end

    AgentsFrontend.user_input_window:open()

    if is_new or focus then
        pcall(function()
            local win = AgentsFrontend.user_input_window
            if vim.api.nvim_win_is_valid(win.win_id) then
                vim.api.nvim_set_current_win(win.win_id)
                vim.api.nvim_win_set_cursor(win.win_id, { 1, 0 })
                vim.cmd("startinsert")
            end
        end)
    end
end

--- Read the input box contents, clear it, and submit.
function AgentsFrontend.submit_from_input_window()
    if not AgentsFrontend.user_input_window then
        return
    end
    local bufnr = AgentsFrontend.user_input_window.buffer_number
    local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")

    -- * clear the input buffer after reading
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })

    AgentsFrontend.submit_user_message(text)

    -- * keep focus in the input window, ready for the next message
    pcall(function()
        local win = AgentsFrontend.user_input_window
        if vim.api.nvim_win_is_valid(win.win_id) then
            vim.api.nvim_set_current_win(win.win_id)
            vim.api.nvim_win_set_cursor(win.win_id, { 1, 0 })
            vim.cmd("startinsert")
        end
    end)
end

function AgentsFrontend.follow_up_command()
    -- take follow up after end of prior response message from assistant
    --  if already a M.trace then add to that with a new message
    --  leave content as is in the buffer, close enough to what it would be if redrawn
    --  and I don't use the buffer contents for past messages
    --  so, just copy it out into a new message from user
    AgentsFrontend.ensure_chat_window_is_open()
    local start_line_base0 = AgentsFrontend.chat_window.followup_starts_at_line_0indexed or 0
    local user_message = AgentsFrontend.chat_window.buffer:get_lines_from(start_line_base0)
    AgentsFrontend.chat_window.buffer:scroll_cursor_to_end_of_buffer()
    vim.cmd("normal! o") -- move to end of buffer, add new line below to separate subsequent follow up response message

    local trace = AgentsFrontend.trace
    if not trace then
        opts = {
            -- simulate calling the same as the nvim AskAgent user command:
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

    send_trace_follow_up(user_message)
end

function ask_dump_agent_trace_command()
    local trace = AgentsFrontend.trace
    if not trace then
        print("no trace to dump")
        return
    end
    trace:dump()
end

function AgentsFrontend.clear_chat_command()
    if AgentsFrontend.chat_window then
        AgentsFrontend.chat_window:clear()
    end
    AgentsFrontend.trace = nil
end

local function remove_last_message(args)
    if not AgentsFrontend.trace or not AgentsFrontend.trace.messages then
        error("no messages to remove")
        return
    end

    local current_count = #AgentsFrontend.trace.messages
    local requested_count = tonumber(args.fargs[1]) or 1
    local actual_count = math.min(requested_count, current_count)
    if requested_count ~= actual_count then
        log:info(string.format("Requested to remove %d messages but only %d exist; removing all %d.", requested_count, current_count, actual_count), vim.log.levels.WARN)
    end

    local removed_messages = {}
    for _ = 1, actual_count do
        local removed = table.remove(AgentsFrontend.trace.messages) -- removes last message by default
        table.insert(removed_messages, removed)
    end
    log:info("Removed messages", vim.inspect(removed_messages))
    -- update_ui_chat_viewer(AgentsFrontend.trace) -- TODO IIRC I cannot easily redraw all messages... I wil have that when I add restore.. I can redraw in this case too... for now just leave UX alone unless I can redraw based on line offsets for original messages? i.e. in this case just remove back X offsets ... don't I have a list of those offsets somewhere?
    vim.print("Removed", removed_messages)
end


local function restore_trace(trace_path)
    log:info("Restoring session from: " .. trace_path)
    local success = trace_restorer.restore_session(trace_path)
    if not success then
        error("Failed to restore session from: " .. trace_path)
    end
end

---@param opts table -- options table with args field containing session_id
local function restore_session_command(opts)
    local session_id = opts.args and opts.args:match("^%s*(.-)%s*$") or nil
    local trace_path = trace_restorer.resolve_trace_path(session_id)
    if not trace_path then
        local msg = session_id
            and ("Trace file not found for: " .. session_id)
            or "No trace files found to restore"
        error(msg)
        return
    end
    restore_trace(trace_path)
end

local function restore_trace_command(opts)
    local trace_path = opts.args
    if not trace_path or trace_path == "" then
        error("No trace path provided")
    end
    restore_trace(trace_path)
end


---Checks connectivity to the model server by calling /v1/models and notifies the result.
function AgentsFrontend.check_model_command()
    local model_slug = config.get_agents_model()
    local base_url = config.get_base_url(model_slug)
    if not base_url then
        notify.error("no endpoint configured for model '" .. tostring(model_slug) .. "'", { title = "AskAgentCheckModel" })
        return
    end

    local response = LlamaServerClient.get_models(base_url, { connect_timeout = 5, max_time = 10 })
    if not response or response.code ~= 200 then
        notify.error("/v1/models FAILED at " .. base_url .. " (http " .. tostring(response and response.code or "nil") .. ")", { title = "AskAgentCheckModel" })
        return
    end

    local data = response.body and response.body.data
    if type(data) ~= "table" or #data == 0 then
        notify.warn("/v1/models OK at " .. base_url .. " but no models returned", { title = "AskAgentCheckModel" })
        return
    end

    local model_names = vim.tbl_map(function(m)
        return m.id or "?"
    end, data)
    notify.info("OK - " .. table.concat(model_names, ", ") .. " (via " .. base_url .. ")", {
        title = "AskAgentCheckModel",
        fg = "#4ecb71", -- green success
    })
end

function AgentsFrontend.setup()
    -- * AskAgent
    vim.api.nvim_create_user_command(
        "AskAgent",
        ask_agent_command,
        { range = true, nargs = 1, complete = prompt_parser.SlashCommandCompletion }
    )

    -- *** AskOpenAI Agent Commands ***
    vim.api.nvim_create_user_command("AskAgentRemoveLastMessage", remove_last_message, {
        nargs = "?",
        desc = "Remove last N messages from AskOpenAI agent trace (default: 1)"
    })
    vim.api.nvim_create_user_command("AskAgentCheckModel", AgentsFrontend.check_model_command, {
        desc = "Check the model server (/v1/models) and notify the result"
    })
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

    vim.keymap.set('n', '<leader>aa', AgentsFrontend.abort_request, { noremap = true })
    vim.keymap.set('n', '<leader>ai', AgentsFrontend.interrupt_agent, { noremap = true, desc = 'interrupt the agent mid-completion and deliver queued messages' })
    vim.keymap.set('n', '<leader>ac', ':<C-u>:AskAgent /tools /norag /coordinator ', { noremap = true })
    vim.keymap.set('n', '<leader>al', AgentsFrontend.clear_chat_command, { noremap = true })
    vim.keymap.set('n', '<leader>af', AgentsFrontend.follow_up_command, { noremap = true })
    vim.keymap.set('n', '<leader>ao', AgentsFrontend.ensure_chat_window_is_open, { noremap = true })
    vim.keymap.set('n', '<leader>au', function() AgentsFrontend.ensure_user_input_window_is_open(true) end, { noremap = true, desc = 'open/focus the user message input box' })
    vim.keymap.set('n', '<leader>as', AgentsFrontend.check_model_command, { noremap = true, desc = 'Check model server /v1/models' })
    -- * long-trace buffer simulation (replicate chat window lag; watch it live)
    vim.keymap.set('n', '<leader>abs', function()
        require('ask-openai.agents.viewer.buffers_integration_tests').run_simulation()
    end, { noremap = true, desc = 'run long-trace buffer simulation in a chat window' })
    vim.keymap.set('n', '<leader>ar', function() require("ask-openai.agents.viewer.session_restore_list"):open() end, { noremap = true })

    vim.api.nvim_create_user_command("AskDumpAgentTrace", ask_dump_agent_trace_command, {})

    -- * AgentSessionRestore
    vim.api.nvim_create_user_command("AskAgentRestoreSessionID", restore_session_command, {
        nargs = "?",
        desc = "Restore a past agent session/trace into the chat viewer (session_id is unix timestamp or *-trace.json filename; omit for most recent)"
    })
    vim.api.nvim_create_user_command("AskAgentRestoreTrace", restore_trace_command, {
        nargs = "?",
        desc = "Restore a past agent trace file into the chat viewer"
    })
    -- * AskViewTrace
    vim.api.nvim_create_user_command("AskViewTrace", function(opts)
        TracePager.open_trace_viewer(opts.args)
    end, {
        nargs = 1,
        desc = "Open a trace JSON file in a terminal pager with navigation keymaps (n/p for next/prev line, nu/pu for USER, na/pa for ASSISTANT)"
    })

    vim.api.nvim_create_user_command("AskAgentLoadLastUserMessage", AgentsFrontend.load_last_user_message, {
        nargs = "?",
        desc = "Load last saved user message"
    })
end

return AgentsFrontend
