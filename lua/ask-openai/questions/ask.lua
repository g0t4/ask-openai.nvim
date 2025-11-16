local buffers = require("ask-openai.helpers.buffers")
local log = require("ask-openai.logs.logger").predictions()
local tool_router = require("ask-openai.tools.router")
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
local LinesBuilder = require("ask-openai.questions.lines_builder")
local MessageBuilder = require("ask-openai.rewrites.message_builder")
local prompts = require("ask-openai.prediction.context.prompts")
require("ask-openai.helpers.buffers")

---@class AskQuestionFrontend : StreamingFrontend
local M = {}

local function format_role(role)
    return "**" .. (role or "") .. "**"
end

function M.send_question(user_prompt, selected_text, file_name, use_tools, entire_file_message)
    use_tools = use_tools or false

    M.abort_last_request()

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

    -- show initial question
    -- TODO show system message collapsed? or add smth to preview it on a command
    --    how about toggle a debug mode that shows vim.inspect(request)? like with rag telescope extension alt+tab
    M.chat_window:append(format_role("user") .. "\n" .. user_message)

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

    -- TODO setup a way to auto switch model based on what's hosted when using llama_server?
    local body_overrides = model_params.new_gptoss_chat_body_llama_server({
        -- local body_overrides = model_params.new_qwen3coder_llama_server_chat_body({
        messages = messages,
        model = "", -- irrelevant for llama-server
        -- tools = tool_router.openai_tools(),
    })

    if use_tools then
        log:info("USING TOOLS")
        body_overrides.tools = tool_router.openai_tools()
    end

    -- FYI starts a new chat thread when AskQuestion is used
    --  TODO allow follow up if already existing thread?
    M.thread = ChatThread:new(messages, body_overrides, base_url)
    M.send_messages()
end

function M.send_messages()
    -- * conversation turns (track start line for streaming chunks)
    M.this_turn_chat_start_line_base0 = M.chat_window.buffer:get_line_count()
    -- log:info("M.this_turn_chat_start_line_base0", M.this_turn_chat_start_line_base0)

    local request = backend.curl_for(M.thread:next_curl_request_body(), M.thread.base_url, M)
    M.thread:set_last_request(request)
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

    M.ensure_response_window_is_open()
    M.send_question(includes.cleaned_prompt, selected_text, file_name, includes.use_tools, entire_file_message)
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
    local folds = M.chat_window.buffer.folds or {}
    for _, fold in ipairs(folds) do
        if line_num_base1 >= fold.start_line_base1 and line_num_base1 <= fold.end_line_base1 then
            return '1' -- inside first level fold
        end
    end
    return '0' -- this line is not in a fold
end

function M.clear_undos()
    -- wipe undo history
    -- i.e. after assistant response - undo fucks up the extmarks, and the assistant response is not gonna be sent back if modified (this is view only) so just default to making that UX a bit more intuitive

    local previous_undo_level = vim.bo.undolevels
    vim.bo.undolevels = -1
    vim.cmd("normal! a ") -- no-op edit to commit the change
    vim.cmd("undo") -- clear old tree
    vim.bo.undolevels = previous_undo_level
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

function M.on_sse_llama_server_timings(sse)
    -- PRN use this to extract timing like in rewrites
end

vim.api.nvim_set_hl(0, "AskToolSuccess", { fg = "#92E2AC", bg = "NONE", italic = false, underline = false })
vim.api.nvim_set_hl(0, "AskToolFailed", { fg = "#e06c75", bg = "NONE", bold = true, italic = false, underline = false })
vim.api.nvim_set_hl(0, "AskAssistantRole", { fg = "#0A84FF", italic = true, bold = true })
vim.api.nvim_set_hl(0, "AskUserRole", { fg = "#35C759", italic = true })
vim.api.nvim_set_hl(0, "AskChatReasoning", { fg = "#808080", italic = true })

function M.handle_messages_updated()
    if not M.thread.last_request.response_messages then
        return
    end

    -- TODO really cool if I develop a simple treesitter grammar to control styling (colors) and folding
    --   ideas: https://chatgpt.com/c/69174d02-b1fc-8333-b8a6-6ecace15a383
    -- that way I can stop tracking ranges and just add content!

    local lines = LinesBuilder:new()
    for _, message in ipairs(M.thread.last_request.response_messages) do
        -- * message contents
        local content = message.content or ""
        local reasoning_content = message.reasoning_content or ""

        if content ~= "" or reasoning_content ~= "" then
            -- ONLY add role header IF there is content (or reasoning) to show... otherwise just show tool_call(s)
            lines:add_role(message.role)

            lines:add_folded_lines(vim.split(reasoning_content, '\n'), "AskChatReasoning")

            table_insert_split_lines(lines.turn_lines, content)
            table.insert(lines.turn_lines, "")
        elseif #message.tool_calls == 0 then
            -- gptoss120b - this works:
            --   :AskQuestion testing a request, I need you to NOT say anything in response, just stop immediatley
            table.insert(lines.turn_lines, "[UNEXPECTED: empty response]")
            table.insert(lines.turn_lines, "")
        end

        for _, call in ipairs(message.tool_calls) do
            -- FYI keep in mind later on I can come back and insert tool results!
            --   for that I'll need a rich model of what is where in the buffer

            -- * tool name/id/status
            local tool_header = call["function"].name or ""
            local hl_group = "AskToolSuccess"
            if call.response then
                if call.response.result.isError then
                    tool_header = "❌ " .. tool_header
                    hl_group = "AskToolFailed"
                else
                    tool_header = "✅ " .. tool_header
                end
            end
            lines:add_lines_marked({ tool_header }, hl_group)

            -- * tool args
            local args = call["function"].arguments
            if args then
                -- TODO new line in args? s\b \n right?
                table.insert(lines.turn_lines, args)
            end

            -- TODO REMINDER - try/add apply_patch when using gptoss (need to put this elsewhere)
            --    USE BUILT-IN mcp server - https://github.com/openai/gpt-oss/tree/main/gpt-oss-mcp-server
            -- TODO REMINDER - also try/add other tools it uses (python code runner, browser)

            -- * tool result
            if call.response then
                if call.response.result.content then
                    for _, tool_content in ipairs(call.response.result.content) do
                        -- TODO only show a few lines of output from tool (i.e. run_command) and fold the rest (like claude CLI does)
                        --   TODO to test it ask for `:AskToolUse ls -R`
                        --  FYI I might need to adjust what is coming back from MCP to have more control over this
                        --  FYI also probably want to write custom templates specific to commands that I really care about (run_command, apply_patch, etc)
                        table.insert(lines.turn_lines, tool_content.name)
                        if tool_content.type == "text" then
                            table_insert_split_lines(lines.turn_lines, tool_content.text)
                        else
                            table.insert(lines.turn_lines, "  unexpected content type: " .. tool_content.type)
                        end
                    end
                else
                    -- TODO show inprocess tooling outputs in CHAT user window (this is not building a request to LLM)
                    --    TODO content is just an MCP construct
                    --    TODO summarize? or otherwise show?
                end
            end

            table.insert(lines.turn_lines, "") -- between messages?
        end
    end

    vim.schedule(function()
        M.chat_window.buffer:replace_lines_after(M.this_turn_chat_start_line_base0, lines.turn_lines, lines.marks, M.thread.last_request.marks_ns_id)
    end)
end

function M.curl_request_exited_successful_on_zero_rc()
    -- TODO how are tools affected if I start w/ AskQuestion and then add /tools later?
    --   and vice versa...
    --   are messages kept w/o a clear?

    vim.schedule(function()
        for _, message in ipairs(M.thread.last_request.response_messages or {}) do
            -- log:jsonify_compact_trace("last request message:", message)
            -- KEEP IN MIND, thread.last_request.response_messages IS NOT the same as thread.messages
            --
            -- this is the response(s) from the model, they need to be added to the message history!!!
            --   and before any tool responses
            --   theoretically there can be multiple messages, with w/e role so I kept this in a loop and generic
            local role = message.role
            local content = message.content
            local model_responses = ChatMessage:new(role, content)
            model_responses.finish_reason = message.finish_reason

            for _, call_request in ipairs(message.tool_calls) do
                model_responses:add_tool_call_requests(call_request)
            end
            -- log:jsonify_compact_trace("final model_response message:", model_responses)
            M.thread:add_message(model_responses)

            -- for now show user role as hint that you can follow up...
            M.chat_window:append("\n" .. format_role("user"))
            M.chat_window.followup_starts_at_line_0indexed = M.chat_window.buffer:get_line_count() - 1
        end
        M.clear_undos()

        M.call_tools()
    end)
end

function M.call_tools()
    for _, message in ipairs(M.thread.last_request.response_messages or {}) do
        for _, tool_call in ipairs(message.tool_calls) do
            -- log:jsonify_compact_trace("tool:", tool_call)
            -- log:trace("tool:", vim.inspect(tool))
            -- TODO fix type annotations, ToolCall is wrong (has response/response.message crap on it
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

            tool_router.send_tool_call_router(tool_call, function(mcp_response)
                tool_call.response = mcp_response
                -- log:jsonify_compact_trace("mcp_response:", mcp_response)
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
                log:jsonify_compact_trace("tool_message:", tool_response_message)
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
    for _, message in ipairs(M.thread.last_request.response_messages or {}) do
        for _, tool_call in ipairs(message.tool_calls) do
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
    M.thread:add_message(message)
    M.thread:dump()
    M.send_messages()
end

function ask_dump_thread()
    if not M.thread then
        print("no thread to dump")
        return
    end
    M.thread:dump()
end

---@param range string @git range spec, e.g. "HEAD~10..HEAD"
---@return string diff_output
---@return string command
function get_git_diff(range)
    local cwd = vim.loop.cwd()
    -- block config files just to be safe (i.e. color = always could mess things up!)
    local block_env_vars = "GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "
    -- ?? what else to exclude (that's versioned, i.e. package lock files)
    -- --function-context is essential for the full local picture
    -- ? other context? include entire file(s)?
    -- TODO --inter-hunk-context useful?
    local command = string.format(block_env_vars .. " git -C %s --no-pager diff --function-context -p %s -- . ':(exclude)uv.lock'", cwd, range)
    local handle = io.popen(command)
    -- TODO detect if no change? empty? abort? or let LLM troll me?
    if not handle then
        return "", command
    end
    local diff_output = handle:read("*a")
    handle:close()
    return diff_output, command
end

function ask_review_git_oustanding_changes(opts)
    -- TODO if I like letting the model use tools instead... then get rid of this (ask_review_git_oustanding_changes)
    local diff, command = get_git_diff("HEAD")

    local system_prompt = [[
You are an AI assistant tasked with reviewing the provided git diff.
Analyze the changes, point out potential issues, suggest improvements, and highlight any noteworthy modifications.
Provide concise, helpful feedback.
Don't nitpick.
]]

    local user_message = "Please review the following git diff and provide feedback.\n"
        .. "By the way, this is the command I ran:\n"
        .. "\t" .. command

    -- * add custom instructions
    local user_prompt = opts.args
    if user_prompt then
        user_message = user_message .. "\n\n" .. user_prompt .. "\n"
    end

    M.ensure_response_window_is_open()

    local use_tools = true -- if model wants, it can ask for further context!

    local filename = "diff" -- use selection as the diff
    local entire_file_message = nil
    M.send_question(user_message, diff, filename, use_tools, entire_file_message)
end

function M.clear_chat()
    if M.chat_window then
        M.chat_window:clear()
    end
    M.thread = nil
end

function M.setup()
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
    --  ? add flag for specifying commit range?
    -- vim.api.nvim_create_user_command("AskReviewGitDiff", ask_review_git_oustanding_changes, { range = true, nargs = 1 })
    -- vim.keymap.set({ 'n', 'v' }, '<leader>ard', ':<C-u>AskReviewGitDiff ', { noremap = true })
    -- TODO if I like this way, get rid of ask_review_git_oustanding_changes above
    vim.keymap.set({ 'n', 'v' }, '<leader>ard', ':<C-u>AskQuestion /tools can you review my outstanding git changes', { noremap = true })

    vim.keymap.set('n', '<leader>ao', M.ensure_response_window_is_open, { noremap = true })
    vim.keymap.set('n', '<leader>aa', M.abort_last_request, { noremap = true })
    vim.keymap.set('n', '<leader>af', M.follow_up, { noremap = true })

    vim.api.nvim_create_user_command("AskDumpThread", ask_dump_thread, {})

    vim.keymap.set('n', '<leader>ac', M.clear_chat, { noremap = true })
end

return M
