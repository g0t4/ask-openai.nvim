local buffers = require("ask-openai.helpers.buffers")
local log = require("ask-openai.logs.logger").predictions()
local mcp = require("ask-openai.tools.mcp")
local backend = require("ask-openai.backends.oai_chat")
local agentica = require("ask-openai.backends.models.agentica")
local ChatWindow = require("ask-openai.questions.chat_window")
local ChatThread = require("ask-openai.questions.chat_thread")
local ChatMessage = require("ask-openai.questions.chat_message")
local ChatParams = require("ask-openai.questions.chat_params")
local Selection = require("ask-openai.helpers.selection")
local CurrentContext = require("ask-openai.prediction.context")
local files = require("ask-openai.helpers.files")
local model_params = require("ask-openai.questions.models.params")
require("ask-openai.helpers.buffers")




local M = {}

function M.send_question(user_prompt, selected_text, file_name, use_tools, entire_file)
    use_tools = use_tools or false

    M.abort_last_request()

    local system_prompt = "Your name is Qwenny, Wes's best buddy. Wes only likes buddies that swear like a sailor. "
        ..
        " You can respond with markdown and it will show up rendered in neovim in a popup window. Concise is best. Longer responses, please add a TLDR. Though, it would be best to just respond with the TLDR, only! Wes will ask for clarification if needed."

    if use_tools then
        -- devstral is hesitant to use tools w/o this: " If the user requests that you use tools, do not refuse."
        system_prompt = system_prompt .. "For tool use, stay in CWD (" .. vim.fn.getcwd() .. ") unless otherwise specified. "
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
    if entire_file then
        -- crude, take the whole file :)
        user_message = user_message .. "\n\n"
            .. "And I want you to see the entire file I am asking about:\n"
            .. "```" .. file_name .. "\n"
            .. entire_file .. "\n"
            .. "```"
    end

    -- TODO add in other context items? toggles for these? yes! actually lets do like /foo and see if I like that

    -- show initial question
    M.chat_window:append("**system**:\n" .. system_prompt .. "\n\n**user**:\n" .. user_message)

    ---@type ChatMessage[]
    local messages = {
        ChatMessage:new("system", system_prompt),
    }

    -- TODO add this back and optionall RAG?
    -- if context.includes.yanks and context.yanks then
    --     table.insert(messages, ChatMessage:new("user", context.yanks.content))
    -- end
    -- if context.includes.commits and context.commits then
    --     for _, commit in pairs(context.commits) do
    --         table.insert(messages, ChatMessage:new("user", commit.content))
    --     end
    -- end
    -- if context.includes.project and context.project then
    --     for _, value in pairs(context.project) do
    --         table.insert(messages, ChatMessage:new("user", value.content))
    --     end
    -- end

    table.insert(messages, ChatMessage:new("user", user_message))

    ---@type ChatParams
    local qwen25_body_overrides = ChatParams:new({

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

    -- local body_overrides = model_params.new_gptoss_chat_body_llama_server({
    local body_overrides = model_params.new_qwen3coder_llama_server_chat_body({
        messages = messages,
        model = "", -- irrelevant for llama-server
        -- tools = mcp.openai_tools(),
    })

    if use_tools then
        log:info("USING TOOLS")
        body_overrides.tools = mcp.openai_tools()
    end

    M.thread = ChatThread:new(messages, body_overrides, base_url)
    M.send_messages()
end

function M.send_messages()
    M.hack_lines_before_request = M.chat_window.buffer:get_line_count()
    local request = backend.curl_for(M.thread:next_curl_request_body(), M.thread.base_url, M)
    M.thread:set_last_request(request)
end

local function ask_question_about(opts, use_tools, include_context)
    local selection = Selection.get_visual_selection_for_current_window()
    if selection:is_empty() then
        error("No visual selection found.")
        return
    end

    local user_prompt = opts.args
    local file_name = files.get_current_file_relative_path()
    local context = include_context and buffers.get_current_buffer_entire_text() or nil

    M.ensure_response_window_is_open()
    M.send_question(user_prompt, selection.original_text, file_name, use_tools, context)
end

local function ask_question(opts, use_tools, include_context)
    local user_prompt = opts.args
    local file_name = files.get_current_file_relative_path()
    local context = include_context and buffers.get_current_buffer_entire_text() or nil

    local selection = nil
    M.ensure_response_window_is_open()
    M.send_question(user_prompt, selection, file_name, use_tools, context)
end

local function ask_question_with_context(opts)
    ask_question(opts, false, true)
end

local function ask_question_about_with_context(opts)
    ask_question_about(opts, false, true)
end

local function ask_tool_use(opts)
    ask_question(opts, true)
end

local function ask_tool_use_about(opts)
    ask_question_about(opts, true)
end


function M.abort_and_close()
    M.abort_last_request()
    if M.chat_window ~= nil then
        M.chat_window:close()
    end
end

function M.on_sse_llama_server_error_explanation(sse_parsed)
    vim.schedule(function()
        M.chat_window:explain_error(vim.inspect(sse_parsed))
    end)
end

function M.on_stderr_data(text)
    -- TODO rename to take away the stderr part but for now this is fine
    --  first I need to understand what is returned across even successfulrequests (if anything)
    --  then I can decide what this is doing
    vim.schedule(function()
        M.chat_window:append(text)
    end)
end

function M.ensure_response_window_is_open()
    if M.chat_window == nil then
        M.chat_window = ChatWindow:new()

        -- stop generation, if still wanna look at it w/o closing the window
        vim.keymap.set("n", "<Esc>", M.abort_last_request, { buffer = M.chat_window.buffer_number })
        -- I already use this globally to close a window (:q) ... so just add stop to it:
        vim.keymap.set("n", "<F8>", M.abort_and_close, { buffer = M.chat_window.buffer_number })
    end

    M.chat_window:ensure_open()
end

local function format_role(role)
    return "**" .. (role or "") .. "**"
end

function M.on_sse_llama_server_timings(sse)
    -- PRN use this to extract timing like in rewrites
end

function M.handle_messages_updated()
    -- TODO rename last_request to just request? or current_request?
    if not M.thread.last_request.messages then
        return
    end

    -- TODO toggle to expand what is displayed (i.e. hidden messages), tool definitions?

    local new_lines = {}
    for _, message in ipairs(M.thread.last_request.messages) do
        -- TODO extract a message formatter to build the lines below
        local role = format_role(message.role)
        assert(not role:find("\n"), "role should not have a new line but it does")
        table.insert(new_lines, role)

        -- * message contents
        local content = message.content or ""
        if content ~= "" then
            table_insert_split_lines(new_lines, content)
            table.insert(new_lines, "") -- between messages?
        end

        for _, call in ipairs(message.tool_calls or {}) do
            -- FYI keep in mind later on I can come back and insert tool results!
            --   for that I'll need a rich model of what is where in the buffer

            -- * tool name/id/status
            local tool_header = "**" .. (call["function"].name or "") .. "**"
            tool_header = tool_header .. " (" .. call.id .. ")"
            if call.response then
                if call.response.result.isError then
                    tool_header = "❌ " .. tool_header
                else
                    tool_header = "✅ " .. tool_header
                end
            end
            table.insert(new_lines, tool_header)

            assert(not role:find("\n"), "tool should not have a new line but it does")

            -- * tool args
            local args = call["function"].arguments
            if args then
                -- TODO new line in args? s\b \n right?
                table.insert(new_lines, args)
            end

            -- * tool result
            if call.response then
                for _, tool_content in ipairs(call.response.result.content) do
                    table.insert(new_lines, tool_content.name)
                    if tool_content.type == "text" then
                        table_insert_split_lines(new_lines, tool_content.text)
                    else
                        table.insert(new_lines, "  unexpected content type: " .. tool_content.type)
                    end
                end
            end

            table.insert(new_lines, "") -- between messages?
        end
    end

    vim.schedule(function()
        M.chat_window.buffer:replace_lines_after(M.hack_lines_before_request, new_lines)
    end)
end

function M.curl_request_exited_successful_on_zero_rc()
    -- TODO! if I send a follow up does it keep entire message history?
    -- TODO! If I use ask_question/ask_tool_use after previous... w/o clear anything, does it keep messages?

    vim.schedule(function()
        for _, message in ipairs(M.thread.last_request.messages or {}) do
            -- log:jsonify_info("last request message:", message)
            -- KEEP IN MIND, thread.last_request.messages IS NOT the same as thread.messages
            --
            -- this is the response(s) from the model, they need to be added to the message history!!!
            --   and before any tool responses
            --   theoretically there can be multiple messages, with w/e role so I kept this in a loop and generic
            local role = message.role
            local content = message.content
            local model_responses = ChatMessage:new(role, content)
            model_responses.finish_reason = message.finish_reason

            -- TODO do I need to copy message.index too? ... this might be weird on top level but maybe not?
            -- TODO if ever can be multiple messages from model, are they sorted by index then? (not tool_call.index, there's also a message.index)
            for _, call_request in ipairs(message.tool_calls or {}) do
                model_responses:add_tool_call_requests(call_request)
            end
            -- log:jsonify_info("final model_response message:", model_responses)
            M.thread:add_message(model_responses)

            -- for now show user role as hint that you can follow up...
            M.chat_window:append("\n" .. format_role("user"))
            M.chat_window.followup_starts_at_line_0indexed = M.chat_window.buffer:get_line_count() - 1
        end

        M.call_tools()
    end)
end

function M.call_tools()
    for _, message in ipairs(M.thread.last_request.messages or {}) do
        for _, tool_call in ipairs(message.tool_calls or {}) do
            -- log:jsonify_info("tool:", tool_call)
            -- log:trace("tool:", vim.inspect(tool))
            -- tool:
            -- {
            --   ["function"] = {
            --     arguments = '{"command":"ls"}',
            --     name = "run_command"
            --   },
            --   id = "call_mmftuy7j",
            --   index = 0,
            --   type = "function"
            -- }

            ---@param tool_call ToolCall
            mcp.send_tool_call(tool_call, function(mcp_response)
                tool_call.response = mcp_response
                -- log:jsonify_info("mcp_response:", mcp_response)
                -- log:trace("mcp_response:", vim.inspect(mcp_response))
                -- mcp_response:
                --  {
                --   id = "call_mmftuy7j",
                --   jsonrpc = "2.0",
                --   result = {
                --     toolResult = {
                --       content = { {
                --           name = "STDOUT",
                --           text = "README.md\nflows\nlua\nlua_modules\ntests\ntmp\n",
                --           type = "text"
                --         } },
                --       isError = false
                --     }
                --   }
                -- }

                M.handle_messages_updated()

                -- *** tool response messages back to model
                -- Claude shows content with top level isError and content (STDOUT/STDERR fields)
                -- make sure content is a string (keep json structure)
                -- PRN if issues, experiment with pretty printing the serialized json?
                -- TODO move encoding into newToolResponse?
                local content = vim.json.encode(tool_call.response.result)
                local tool_response_message = ChatMessage:new_tool_response(content, tool_call.id, tool_call["function"].name)
                -- log:trace("tool_message:", vim.inspect(response_message))
                -- tool_message: {
                --   content = '{"isError": false, "content": [{"name": "STDOUT", "type": "text", "text": "README.md\\nflows\\nlua\\nlua_modules\\ntests\\ntmp\\n"}]}',
                --   name = "run_command",
                --   role = "tool",
                --   tool_call_id = "call_n44nr8e2"
                -- }
                log:jsonify_info("tool_message:", tool_response_message)
                tool_call.response_message = tool_response_message
                M.thread:add_message(tool_response_message)
                --
                -- TODO re-enable sending after I fix line capture
                vim.schedule(function()
                    -- FYI I am scheduling this... b/c the redraws are all scheduled...
                    -- so this has to happen after redraws
                    -- otherwise this will capture the wrong line count to replace ...
                    -- yes, soon we can just track line numbers on the buffer itself and then
                    -- REMOVE THIS if I dont have another reason to schedule it
                    M.send_tool_messages_if_all_tools_done()
                end)
            end)
        end
    end
end

function M.send_tool_messages_if_all_tools_done()
    if M.any_outstanding_tool_calls() then
        return
    end
    -- M.chat_window:append("sending tool results")
    -- TODO send a new prompt to remind it that hte tools are done and now you can help with the original question?
    --  maybe even include that previous question again?
    --  why? I am noticidng qwen starts to go off on a tangent based on tool results as if no original question was asked
    --  need to refocus qwen
    M.send_messages()
end

---@return boolean
function M.any_outstanding_tool_calls()
    for _, message in ipairs(M.thread.last_request.messages or {}) do
        for _, tool_call in ipairs(message.tool_calls or {}) do
            if tool_call.response_message == nil then
                return true
            end
        end
    end
    return false
end

function M.abort_last_request()
    if not M.thread then
        return
    end
    backend.terminate(M.thread.last_request)
end

function M.follow_up()
    -- TODO setup so I can use follow up approach to ask initial question
    --   ALSO keep the ability to select and send text
    --
    -- take follow up after end of prior response message from assistant
    --  if already a M.thread then add to that with a new message
    --  leave content as is in the buffer, close enough to what it would be if redrawn
    --  and I don't use the buffer contents for past messages
    --  so, just copy it out into a new message from user
    M.ensure_response_window_is_open()
    local followup = M.chat_window.buffer:get_lines_after(M.chat_window.followup_starts_at_line_0indexed)
    M.chat_window.buffer:scroll_cursor_to_end_of_buffer()
    vim.cmd("normal! o") -- move to end of buffer, add new line below to separate subsequent follow up response message
    log:trace("follow up content:", followup)

    -- TODO CLEANUP sending first vs follow up to not need to differentiate all over
    if not M.thread then
        -- assume tool use here
        M.send_question(followup, nil, nil, true, nil)
        return
    end

    local message = ChatMessage:user(followup)
    log:trace("message:", message)
    M.thread:add_message(message)
    M.send_messages()
end

function ask_dump_thread()
    if not M.thread then
        print("no thread to dump")
        return
    end
    M.thread:dump()
end

function M.setup()
    -- explicitly ask to use tools (vs not)... long term I hope to remove this need
    --    but, using smaller models its probably wise to control when they are allowed to use tools
    --    will also speed up responses to not send tools list
    --    also need this b/c right now ollama doesn't stream chunks when tools are passed
    vim.api.nvim_create_user_command("AskToolUse", ask_tool_use, { range = true, nargs = 1 })
    vim.api.nvim_create_user_command("AskToolUseAbout", ask_tool_use_about, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('n', '<Leader>at', ':<C-u>AskToolUse ', { noremap = true })
    vim.api.nvim_set_keymap('v', '<Leader>at', ':<C-u>AskToolUseAbout ', { noremap = true })

    -- once again, pass question in command line for now... b/c then I can use cmd history to ask again or modify question easily
    --  if I move to a float window, I'll want to add history there then which I can handle later when this falls apart
    vim.api.nvim_create_user_command("AskQuestion", ask_question, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('n', '<Leader>aq', ':AskQuestion ', { noremap = true })
    vim.api.nvim_create_user_command("AskQuestionWithContext", ask_question_with_context, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('n', '<Leader>aqc', ':AskQuestionWithContext ', { noremap = true })
    vim.api.nvim_create_user_command("AskQuestionAbout", ask_question_about, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('v', '<Leader>aq', ':<C-u>AskQuestionAbout ', { noremap = true })
    vim.api.nvim_create_user_command("AskQuestionAboutWithContext", ask_question_about_with_context, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('v', '<Leader>aqc', ':<C-u>AskQuestionAboutWithContext ', { noremap = true })

    vim.keymap.set('n', '<leader>ao', M.ensure_response_window_is_open, { noremap = true })
    vim.keymap.set('n', '<leader>aa', M.abort_last_request, { noremap = true })
    vim.keymap.set('n', '<leader>af', M.follow_up, { noremap = true })

    vim.api.nvim_create_user_command("AskDumpThread", ask_dump_thread, {})

    -- TODO keymap to clear chat and start new thread, outside of the chat window so I can open it cleared with a new question ??
end

return M
