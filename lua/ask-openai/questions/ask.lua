local buffers = require("ask-openai.helpers.buffers")
local log = require("ask-openai.prediction.logger").predictions()
local mcp = require("ask-openai.tools.mcp")
local backend = require("ask-openai.backends.oai_chat")
local agentica = require("ask-openai.backends.models.agentica")
local ChatWindow = require("ask-openai.questions.chat_window")
local ChatThread = require("ask-openai.questions.chat_thread")
local ChatMessage = require("ask-openai.questions.chat_message")
local M = {}


function M.send_question(user_prompt, code, file_name, use_tools)
    M.abort_last_request()

    local system_prompt = "You are a neovim AI plugin. Your name is Neo Vim. "
        .. " Please respond with markdown formatted text"

    local user_message = user_prompt
    if code then
        -- would make sense to fold the code initially
        user_message = user_message
            .. ". Here is my code from " .. file_name
            .. ":" .. code
    end

    -- show initial question
    M.chat_window:append("**system**:\n" .. system_prompt .. "\n\n**user**:\n" .. user_message)

    ---@type ChatMessage[]
    local qwen_messages = {
        { role = "system", content = system_prompt },
        { role = "user",   content = user_message },
    }

    ---@type ChatParams
    local qwen_params = {

        model = "qwen2.5-coder:7b-instruct-q8_0", -- btw -base- does terrible here :)
        -- model = "gemma3:12b-it-q8_0", -- btw -base- does terrible here :)
        -- temperature = 0.2, -- TODO what temp?
        -- PRN limit num_predict?

        -- FYI - ollama, be careful w/ `num_ctx`, can't set it with OpenAI compat endpoints (whereas can pass with /api/generate)
        --   SEE NOTES about how to set this with env vars / Modelfile instead that can work with openai endpoints (don't have to use /api/generate to fix this issue)
        --   review start logs for n_ctx and during completion it warns if truncated prompt:
        --     level=WARN source=runner.go:131 msg="truncating input prompt" limit=8192 prompt=10552 keep=4 new=8192
    }
    -- /v1/chat/completions
    -- local body = agentica.DeepCoder.build_chat_body(system_prompt, user_message)
    -- PRN split agentica into messages and params

    -- ollama:
    local base_url = "http://ollama:11434"
    --
    -- vllm:
    -- local base_url = "http://build21:8000"
    -- body.model = "" -- dont pass model, use whatever is served

    if use_tools then
        -- TODO impl final test case for streaming tool_calls with vllm!
        qwen_params.tools = mcp.openai_tools()
    end

    M.thread = ChatThread:new(qwen_messages, qwen_params, base_url)
    M.send_messages()
end

function M.send_messages()
    M.hack_lines_before_request = M.chat_window.buffer:get_line_count()
    local request = backend.curl_for(M.thread:next_body(), M.thread.base_url, M)
    M.thread:set_last_request(request)
end

local function ask_question_about(opts, use_tools)
    use_tools = use_tools or false

    local selection = buffers.get_visual_selection()
    if selection:is_empty() then
        error("No visual selection found.")
        return
    end

    local user_prompt = opts.args
    local file_name = vim.fn.expand("%:t")

    M.ensure_response_window_is_open()
    M.send_question(user_prompt, selection.original_text, file_name, use_tools)
end

local function ask_question(opts, use_tools)
    use_tools = use_tools or false

    local user_prompt = opts.args
    M.ensure_response_window_is_open()
    M.send_question(user_prompt, nil, nil, use_tools)
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

-- WIP - callback when non-zero exit code (at end)
--  i.e. if the server times out or the port is not responding:
--  I am going to need to check exit code and if its negative, then show smth...
--  IIRC aborting request triggers a non-zero exit code so need to handle that too to not give false positive warnings
--   worse case once a request is terminated then do not allow showing any other errors or messages from it... that would make sense
--     so have the on exit handler in backend check request status before reporting back!
--
--  TODO should I print std_err messages? along the way? thats only way to show the message to the user
--  TODO should I detect some failures like Failed to connect in on_stderr? and print/pass the message back in that case?
--  TODO synchronize frontend API with rewrite too
--
-- i.e.
-- [4.603]sec [WARN] on_stderr chunk:  curl: (7) Failed to connect to build21 port 8000 after 7 ms: Couldn't connect to server
-- [4.609]sec [ERROR] spawn - non-zero exit code: 7 Signal: 0
--
function M.request_failed()
    -- this is for AFTER the request completes and curl exits
    vim.schedule(function()
        M.chat_window:append("\nerror: request failed")
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

function M.signal_deltas()
    -- TODO for lack of a better name, this will trigger a redraw of ChatWindow
    --    OR at least redraw current requests's contents (messages/tool calls, both will stream this way too!)
    -- great way to illustrate how this works:
    log:trace("signal", vim.inspect(M.thread.last_request))
    -- TODO rename last_request to just request? or current_request?
end

function M.process_chunk(text)
    vim.schedule(function()
        M.chat_window:append(text)
    end)
end

function M.process_tool_calls(tool_calls)
    -- for now just write tool dcalls to the buffer
    M.thread.last_request.tool_calls = M.thread.last_request.tool_calls or {}

    -- each time this is called, its a list of tool_call
    -- insert those into overall list (flatten)
    for _, tool_call in ipairs(tool_calls) do
        -- TODO write insertMany
        table.insert(M.thread.last_request.tool_calls, tool_call)
    end

    -- local tool_calls_str = vim.inspect(tool_calls)
    -- M.chat_window:append(tool_calls_str)

    local tool_calls_summmary = {}
    for _, tool_call in ipairs(tool_calls) do
        name = "**" .. tool_call["function"].name
        -- PRN add a "verbose" mode? and show things like id then:
        name = name .. "**" .. " (" .. tool_call.id .. ")"
        table.insert(tool_calls_summmary, name)
        arguments = tool_call["function"].arguments
        table.insert(tool_calls_summmary, arguments)
    end
    vim.schedule(function()
        M.chat_window:append(table.concat(tool_calls_summmary, "\n"))
    end)
end

function M.process_request_completed()
    -- TODO use new aggregated request.messages!!
    --   then resume this:
    --
    --   TODO MOVE tool call setup here... get off of DENORMALIZER
    --
    -- vim.schedule(function()
    --     log:jsonify_info("assistant_message:", assistant_message)
    --     M.call_tools()
    -- end)
end

function M.call_tools()
    -- log:trace("tools:", vim.inspect(M.thread.last_request.tool_calls))
    if M.thread.last_request.tool_calls == {} then
        return
    end
    for _, tool_call in ipairs(M.thread.last_request.tool_calls) do
        log:jsonify_info("tool:", tool_call)
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

        mcp.send_tool_call(tool_call, function(mcp_response)
            tool_call.response = mcp_response
            log:jsonify_info("mcp_response:", mcp_response)
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

            -- M.chat_window:append(vim.inspect(mcp_response))
            -- FYI might be cool to mod the original tool_call display and insert the result there and put the status line on its original name/id?
            --    -- TODO if I have a builder pattern for showing the chat history... I can rebuild it then, or at least rebuild it for the last request's tool calls
            --  that way I can see the cmd + result easily
            local result_summary = {}
            -- FYI ... isError is part of MCP spec, all tools return it IIUC... so this is not coupled to run_command
            if tool_call.response.result.toolResult.isError then
                local failed = "❌ (" .. tool_call.id .. ")"
                table.insert(result_summary, failed)
            else
                local success = "✅ (" .. tool_call.id .. ")"
                table.insert(result_summary, success)
            end
            for _, content in ipairs(tool_call.response.result.toolResult.content) do
                table.insert(result_summary, content.name)
                if content.type == "text" then
                    table.insert(result_summary, content.text)
                else
                    table.insert(result_summary, "  unexpected content type: " .. content.type)
                end
            end
            M.chat_window:append(table.concat(result_summary, "\n"))

            -- Claude shows content with top level isError and content (STDOUT/STDERR fields)
            -- make sure content is a string (keep json structure)
            -- PRN if issues, experiment with pretty printing the serialized json?
            -- TODO move encoding into newToolResponse?
            local content = vim.fn.json_encode(tool_call.response.result.toolResult)
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
            M.send_tool_messages_if_all_tools_done()
        end)
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
    for _, tool_call in ipairs(M.thread.last_request.tool_calls) do
        if tool_call.response_message == nil then
            return true
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
    -- TODO this needs some serious love and rethink keys...
    --   ultimatley I wanna pop open the window and type my prompt it in altogether

    -- take the last paragraph of text in the buffer and ask about it
    --  if already a M.thread then add to that with a new message
    -- can leave paragraph as is in the buffer, just need to copy it to a message to send
    -- copy it
    M.ensure_response_window_is_open()
    local paragraph = M.chat_window.buffer:get_last_paragraph()
    -- log:trace("last paragraph:", paragraph)

    -- TODO CLEANUP sending first vs follow up to not need to differentiate all over
    if not M.thread then
        -- assume tool use here
        M.send_question(paragraph, nil, nil, true)
        return
    end

    local message = ChatMessage:new_user_message(paragraph)
    log:trace("message:", message)
    M.thread:add_message(message)
    M.send_messages()
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
    vim.api.nvim_create_user_command("AskQuestionAbout", ask_question_about, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('v', '<Leader>aq', ':<C-u>AskQuestionAbout ', { noremap = true })
    vim.api.nvim_set_keymap('n', '<Leader>aq', ':AskQuestion ', { noremap = true })

    vim.keymap.set('n', '<leader>ao', M.ensure_response_window_is_open, { noremap = true })
    vim.keymap.set('n', '<leader>aa', M.abort_last_request, { noremap = true })
    vim.keymap.set('n', '<leader>af', M.follow_up, { noremap = true })
end

return M
