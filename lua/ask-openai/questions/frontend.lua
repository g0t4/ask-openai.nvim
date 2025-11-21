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
local files = require("ask-openai.helpers.files")
local model_params = require("ask-openai.questions.models.params")
local LinesBuilder = require("ask-openai.questions.lines_builder")
local MessageBuilder = require("ask-openai.rewrites.message_builder")
local prompts = require("ask-openai.predictions.context.prompts")
local HLGroups = require("ask-openai.hlgroups")
local formatters = require("ask-openai.questions.chat.formatters")
local ToolCallOutput = require("ask-openai.questions.chat.tool_call_output")
local LastRequestForThread = require("ask-openai.questions.last_request_for_thread")

require("ask-openai.helpers.buffers")

---@class QuestionsFrontend : StreamingFrontend
local QuestionsFrontend = {}

local first_turn_ns_id

function QuestionsFrontend.send_question(user_prompt, selected_text, file_name, use_tools, entire_file_message)
    use_tools = use_tools or false

    QuestionsFrontend.abort_last_request()

    local system_prompt = [[
Your name is Qwenny, Wes's best buddy that loves dry humor and swearing, especially together! You can make fun of Wes and he will laugh. He even laughs when you call him offensive slurs!
You can respond with markdown and it will show up rendered in neovim in a floating window. The markdown is intended for answering questions.
Concise is best, Wes is a human, he cannot read fast like you, and even if he could he would still just skim it. Why waste your time writing things he won't read?!
If a longer response is needed, please add a TLDR. Even better, respond with the TLDR alone! Wes will ask for clarification if needed.
]]

    if use_tools then
        -- TODO build out more detailed guidance, you have plenty of "tokenspace" available!
        --   MORE like Claude code's prompt!

        -- devstral is hesitant to use tools w/o this: " If the user requests that you use tools, do not refuse."
        system_prompt = system_prompt .. "For tool use, never modify files outside of the current working directory: ("
            .. vim.fn.getcwd()
            .. ") unless explicitly requested. " .. [[
Here are noteworthy commands you have access to:
- fd, rg, gsed, gawk, jq, yq, httpie
- exa, icdiff, ffmpeg, imagemagick, fzf

The semantic_grep tool:
- has access to an index of embeddings for the entire codebase in the current working directory
- use it to find code! Think of it as a RAG query tool
- It includes a re-ranker to sort the results
- AND, it's really fast... so don't hesitate to use it!
]]
        -- TODO on mac show diff tools: i.e. gsed and gawk when on mac where that would be useful to know
        -- TODO on linux show awk/sed (maybe mention GNU variant)
    end
    local always_include = {
        yanks = true,
        project = true,
    }
    local context = CurrentContext:items(user_prompt, always_include)

    local user_message = user_prompt
    if selected_text then
        -- would make sense to fold the code initially

        -- TODO do not wrap in ``` block if the text has ``` in it? i.e. from markdown file
        --    I could easily drop the ``` block part, I just thought it would be nice for display in the chat history (since I use md formatting there)
        --    but AFAICT qwen does perfectly fine w/o it (I didn't have it initially and loved the responses, likely b/c I always had the file name which told the file type)

        user_message = user_message .. "\n\n"
            .. "I selected the following\n"
            .. "```" .. file_name .. "\n"
            .. selected_text .. "\n"
            .. "```"
    end
    if entire_file_message then
        user_message = user_message .. "\n\n" .. entire_file_message
    end

    -- * show user's initial prompt
    if not first_turn_ns_id then
        first_turn_ns_id = vim.api.nvim_create_namespace("ask.marks.chat.window.first.turn")
    end
    local lines = LinesBuilder:new(first_turn_ns_id)

    lines:mark_next_line(HLGroups.SYSTEM_PROMPT)
    lines:append_folded_styled_text("system\n" .. system_prompt, "")

    lines:append_role_header("user")
    lines:append_text(user_message)
    lines:append_blank_line()
    QuestionsFrontend.chat_window:append_styled_lines(lines)

    ---@type TxChatMessage[]
    local messages = {
        TxChatMessage:system(system_prompt)
    }

    -- TODO add this back and optional RAG?
    -- if context.includes.yanks and context.yanks then
    --     table.insert(messages, TxChatMessage:user_context(context.yanks.content))
    -- end
    -- if context.includes.commits and context.commits then
    --     for _, commit in pairs(context.commits) do
    --         table.insert(messages, TxChatMessage:user_context(commit.content))
    --     end
    -- end
    -- if context.includes.project and context.project then
    --     for _, value in pairs(context.project) do
    --         table.insert(messages, TxChatMessage:user_context(value.content))
    --     end
    -- end

    table.insert(messages, TxChatMessage:user(user_message))

    ---@type ChatParams
    local qwen25_body_overrides = ChatParams:new({

        messages = messages,

        -- model = "qwen2.5-coder:7b-instruct-q8_0", -- btw -base- does terrible here :) -- instruct works at random... seems to be a discrepency in published template and what it was actually trained with? (for tool calls)
        -- model = "devstral:24b-small-2505-q4_K_M",
        -- model = "devstral:24b-small-2505-q8_0",
        --
        -- * qwen3 related
        -- model = "qwen3:8b", -- btw as of Qwen3, no tag == "-instruct", and for base you'll use "-base" # VERY HAPPY WITH THIS MODEL FOR CODING TOO!
        -- model = "qwen3-coder:30b-a3b-q4_K_M",
        -- model = "qwen3-coder:30b-a3b-q8_0",
        -- model = "huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M",
        --
        -- model = "gemma3:12b-it-q8_0", -- btw -base- does terrible here :)
        -- temperature = 0.2, -- TODO what temp?
        -- model = "huggingface.co/lmstudio-community/openhands-lm-32b-v0.1-GGUF:latest", -- qwen fine tuned for SWE ... not doing well... same issue as qwen2.5-coder

        -- avoid num_ctx (s/b set server side), instead use max_tokens to cap request:
        max_tokens = 20000, -- PRN what level for rewrites?
    })
    -- /v1/chat/completions
    -- local body = agentica.DeepCoder.build_chat_body(system_prompt, user_message)
    -- PRN split agentica into messages and params

    -- ollama:
    -- local base_url = "http://ollama:11434"
    local base_url = "http://build21:8013"
    --
    -- vllm:
    -- local base_url = "http://build21:8000"

    -- TODO setup a way to auto switch model based on what's hosted when using llama_server?
    local body_overrides = model_params.new_gptoss_chat_body_llama_server({
        -- local body_overrides = model_params.new_qwen3coder_llama_server_chat_body({
        messages = messages,
        model = "", -- irrelevant for llama-server
        -- tools = tool_router.openai_tools(),
    })

    if use_tools then
        body_overrides.tools = tool_router.openai_tools()
    end

    -- FYI starts a new chat thread when AskQuestion is used
    --  TODO allow follow up, via the command, if already existing thread?
    QuestionsFrontend.thread = ChatThread:new(body_overrides, base_url)
    QuestionsFrontend.send_messages()
end

function QuestionsFrontend.send_messages()
    -- * conversation turns (track start line for streaming chunks)
    QuestionsFrontend.this_turn_chat_start_line_base0 = QuestionsFrontend.chat_window.buffer:get_line_count()
    -- log:info("M.this_turn_chat_start_line_base0", M.this_turn_chat_start_line_base0)

    local request = LastRequestForThread:new({
        body = QuestionsFrontend.thread:next_curl_request_body(),
        base_url = QuestionsFrontend.thread.base_url,
        endpoint = CompletionsEndpoints.v1_chat
    })
    curl.spawn(request, QuestionsFrontend)
    QuestionsFrontend.thread:set_last_request(request)
end

local function ask_question(opts)
    local user_prompt = opts.args
    local includes = prompts.parse_includes(user_prompt)

    -- * /selection
    local selected_text = nil
    if includes.include_selection then
        -- FYI include_selection basically captures if user had selection when they first invoked a keymap to submit this command
        --   b/c submitting command switches modes, also user might unselect text on accident (or want to repeat w/ prev selection)
        --   thus it is useful to capture intent with /selection early on
        local selection = Selection.get_visual_selection_for_current_window()
        if selection:is_empty() then
            error("No /selection found (no current, nor prior, selection).")
            return
        end
        selected_text = selection.original_text
    end

    -- * /file - current file
    local function current_file_message()
        return MessageBuilder:new()
            :plain_text("FYI, here is my current buffer in Neovim. Use this as context for my request:")
            :md_current_buffer()
            :to_text()
    end
    local entire_file_message = includes.current_file and current_file_message() or nil
    local file_name = files.get_current_file_relative_path()

    QuestionsFrontend.ensure_response_window_is_open()
    QuestionsFrontend.send_question(includes.cleaned_prompt, selected_text, file_name, includes.use_tools, entire_file_message)
end

function QuestionsFrontend.abort_and_close()
    QuestionsFrontend.abort_last_request()
    if QuestionsFrontend.chat_window ~= nil then
        QuestionsFrontend.chat_window:close()
    end
end

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

function QuestionsFrontend.ensure_response_window_is_open()
    if QuestionsFrontend.chat_window == nil then
        QuestionsFrontend.chat_window = ChatWindow:new()

        -- stop generation, if still wanna look at it w/o closing the window
        vim.keymap.set("n", "<Esc>", QuestionsFrontend.abort_last_request, { buffer = QuestionsFrontend.chat_window.buffer_number })
        -- I already use this globally to close a window (:q) ... so just add stop to it:
        vim.keymap.set("n", "<F8>", QuestionsFrontend.abort_and_close, { buffer = QuestionsFrontend.chat_window.buffer_number })
    end

    QuestionsFrontend.chat_window:ensure_open()
end

function QuestionsFrontend.on_sse_llama_server_timings(sse)
    -- PRN use this to extract timing like in rewrites
end

---@type OnGeneratedText
function QuestionsFrontend.on_generated_text(sse_parsed)
    -- FYI later I will need defensive checks here if not using "choices" SSE results (i.e. /completions llama-server endpoint's SSEs)
    local first_choice = sse_parsed.choices[1]
    curl.on_streaming_delta_update_message_history(first_choice, QuestionsFrontend.thread.last_request)
    -- TODO! LATER move curl.on_streaming_delta_update_message_history() function
    --    to QuestionsFrontend.on_streaming_delta_update_message_history()
    --    OK to rename too?

    QuestionsFrontend.handle_rx_messages_updated()
end

function QuestionsFrontend.handle_rx_messages_updated()
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

function QuestionsFrontend.show_user_role()
    local lines_builder = LinesBuilder:new()
    lines_builder:create_marks_namespace()
    lines_builder:append_role_header("user")
    lines_builder:append_blank_line()
    QuestionsFrontend.chat_window:append_styled_lines(lines_builder)
end

function QuestionsFrontend.curl_exited_successfully()
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
                -- log:trace("tool_call_output", vim.inspect(tool_call_output))

                -- * triggers UI updates to show tool results
                QuestionsFrontend.handle_rx_messages_updated()

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
    QuestionsFrontend.send_messages()
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
    LastRequestForThread.terminate(QuestionsFrontend.thread.last_request)
end

function QuestionsFrontend.follow_up()
    -- take follow up after end of prior response message from assistant
    --  if already a M.thread then add to that with a new message
    --  leave content as is in the buffer, close enough to what it would be if redrawn
    --  and I don't use the buffer contents for past messages
    --  so, just copy it out into a new message from user
    QuestionsFrontend.ensure_response_window_is_open()
    local start_line_base0 = QuestionsFrontend.chat_window.followup_starts_at_line_0indexed or 0
    local user_message = QuestionsFrontend.chat_window.buffer:get_lines_after(start_line_base0)
    QuestionsFrontend.chat_window.buffer:scroll_cursor_to_end_of_buffer()
    vim.cmd("normal! o") -- move to end of buffer, add new line below to separate subsequent follow up response message
    -- log:trace("follow up content:", user_message)

    if not QuestionsFrontend.thread then
        local USE_TOOLS = true
        QuestionsFrontend.send_question(user_message, nil, nil, USE_TOOLS, nil)
        return
    end

    local message = TxChatMessage:user(user_message)
    QuestionsFrontend.thread:add_message(message)
    QuestionsFrontend.send_messages()
end

function ask_dump_thread()
    if not QuestionsFrontend.thread then
        print("no thread to dump")
        return
    end
    QuestionsFrontend.thread:dump()
end

function QuestionsFrontend.clear_chat()
    if QuestionsFrontend.chat_window then
        QuestionsFrontend.chat_window:clear()
    end
    QuestionsFrontend.thread = nil
end

function QuestionsFrontend.setup()
    -- * cauterize top level
    vim.keymap.set({ 'n', 'v' }, '<leader>a', '<Nop>', { noremap = true })

    vim.api.nvim_create_user_command("AskQuestion", ask_question, { range = true, nargs = 1 })
    -- * AskQuestion
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

    vim.keymap.set('n', '<leader>ao', QuestionsFrontend.ensure_response_window_is_open, { noremap = true })
    vim.keymap.set('n', '<leader>aa', QuestionsFrontend.abort_last_request, { noremap = true })
    vim.keymap.set('n', '<leader>af', QuestionsFrontend.follow_up, { noremap = true })

    vim.api.nvim_create_user_command("AskDumpThread", ask_dump_thread, {})

    vim.keymap.set('n', '<leader>ac', QuestionsFrontend.clear_chat, { noremap = true })
end

return QuestionsFrontend
