local buffers = require("ask-openai.helpers.buffers")
local log = require("ask-openai.prediction.logger").predictions()
local mcp = require("ask-openai.prediction.tools.mcp")
local backend = require("ask-openai.backends.oai_chat")
-- local backend = require("ask-openai.backends.oai_completions")
local agentica = require("ask-openai.backends.models.agentica")

local M = {}

function M.send_question(user_prompt, code, file_name, use_tools)
    M.abort_last_request()

    local system_prompt = "Your name is Ben Dover, you are a neovim AI plugin that answers questions."
        .. " Please respond with markdown formatted text, that will be presented in a floating window."

    local user_message = user_prompt
    if code then
        user_message = user_message
            .. ". Here is my code from " .. file_name
            .. ":\n\n" .. code
    end

    local qwen_chat_body = {
        messages = {
            { role = "system", content = system_prompt },
            { role = "user",   content = user_message },
        },

        model = "qwen2.5-coder:7b-instruct-q8_0", -- btw -base- does terrible here :)
        -- model = "gemma3:12b-it-q8_0", -- btw -base- does terrible here :)
        -- temperature = 0.2, -- TODO what temp?
        -- PRN limit num_predict?

        -- FYI - ollama, be careful w/ `num_ctx`, can't set it with OpenAI compat endpoints (whereas can pass with /api/generate)
        --   SEE NOTES about how to set this with env vars / Modelfile instead that can work with openai endpoints (don't have to use /api/generate to fix this issue)
        --   review start logs for n_ctx and during completion it warns if truncated prompt:
        --     level=WARN source=runner.go:131 msg="truncating input prompt" limit=8192 prompt=10552 keep=4 new=8192
    }

    local qwen_legacy_body = {
        model = "qwen2.5-coder:7b-instruct-q8_0", -- btw -base- does terrible here :)
        prompt = system_prompt .. "\n" .. user_message,
        -- todo temp etc
    }

    -- /v1/chat/completions
    -- local body = agentica.DeepCoder.build_chat_body(system_prompt, user_message)
    local body = qwen_chat_body

    -- /v1/completions
    -- local body = qwen_legacy_body

    -- ollama:
    local base_url = "http://ollama:11434"
    --
    -- vllm:
    -- local base_url = "http://build21:8000"
    -- body.model = "" -- dont pass model, use whatever is served

    if use_tools then
        -- TODO impl streaming tool_call chunking with vllm (it works)!
        --   https://github.com/vllm-project/vllm/issues/7912#issuecomment-2413840297
        --   TODO find out why Coder variant doesn't produce tool calls in vllm whereas non-coder works... and versus in ollama coder variant produces tool calls just fine (I skimmed prompts and they appear the same)
        --   vllm serve Qwen/Qwen2.5-Coder-7B-Instruct --enable-auto-tool-choice --tool-call-parser hermes     # not ever giving tool calls in vllm only
        --   vllm serve Qwen/Qwen2.5-7B-Instruct --enable-auto-tool-choice --tool-call-parser hermes           # giving tool calls
        --   https://qwen.readthedocs.io/en/latest/framework/function_call.html#id8

        -- TODO during follow up I need to be able to change the toggle too

        -- FYI right now ollama doesn't support stream+tools for /v1/chat/completions
        --   if tools set, model responds with one/few chunks after full response is ready
        --   fix might be in the works: https://github.com/ollama/ollama/issues/8887#issuecomment-2640721896
        --
        --   FTR... if tools are requested, it's usually fast (one or two small chunks).. so I don't care if that is not streaming
        --      I get to show the tool_calls to the user and then they'll know (that is very stream like)
        --   issue is... I want any non-tool use (i.e. explanations) to be streaming
        --   WORST CASE - I might need to use a raw /api/chat and format the request and parse response myself.... shouldn't need to though (vllm I bet has streaming tools)
        body.tools = mcp.openai_tools()
    end

    M.last_request = backend.curl_for(body, base_url, M)
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

    M.open_response_window()
    M.send_question(user_prompt, selection.original_text, file_name, use_tools)
end

local function ask_question(opts, use_tools)
    use_tools = use_tools or false

    local user_prompt = opts.args
    M.open_response_window()
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
    vim.cmd(":q", { buffer = M.bufnr })
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
        M.process_chunk("\nerror: request failed")
    end)
end

function M.on_stderr_data(text)
    -- TODO rename to take away the stderr part but for now this is fine
    --  first I need to understand what is returned across even successfulrequests (if anything)
    --  then I can decide what this is doing
    vim.schedule(function()
        M.process_chunk(text)
    end)
end

function M.open_response_window()
    local name = 'Question Response'

    if M.bufnr == nil then
        M.bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(M.bufnr, name)

        -- stop generation, if still wanna look at it w/o closing the window
        vim.keymap.set("n", "<Esc>", M.abort_last_request, { buffer = M.bufnr, nowait = true })
        vim.keymap.set("n", "<F8>", M.abort_and_close, { buffer = M.bufnr }) -- I already use this globally to close a window (:q) ... so just add stop to it
        -- OR, should I let it keep completing in background and then I can come back when its done? for async?
    end

    vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, {}) -- clear the buffer, is there an easier way?

    local screen_lines = vim.api.nvim_get_option_value('lines', {})
    local screen_columns = vim.api.nvim_get_option_value('columns', {})
    local win_height = math.ceil(0.5 * screen_lines)
    local win_width = math.ceil(0.5 * screen_columns)
    local top_is_at_row = screen_lines / 2 - win_height / 2
    local left_is_at_col = screen_columns / 2 - win_width / 2
    local _winid = vim.api.nvim_open_win(M.bufnr, true, {
        relative = 'editor',
        width = win_width,
        height = win_height,
        row = top_is_at_row,
        col = left_is_at_col,
        style = 'minimal',
        border = 'single'
    })
    -- set FileType after creating window, otherwise the default wrap option (vim.o.wrap) will override any ftplugin mods to wrap (and the same for other window-local options like wrap)
    vim.api.nvim_set_option_value('filetype', 'markdown', { buf = M.bufnr })
end

function M.process_chunk(text)
    vim.schedule(function()
        local count_of_lines = vim.api.nvim_buf_line_count(M.bufnr)
        local last_line = vim.api.nvim_buf_get_lines(M.bufnr, count_of_lines - 1, count_of_lines, false)[1]
        local replace_lines = vim.split(last_line .. text, "\n")
        vim.api.nvim_buf_set_lines(M.bufnr, count_of_lines - 1, count_of_lines, false, replace_lines)
    end)
end

function M.process_tool_calls(tool_calls)
    -- for now just write tool dcalls to the buffer
    local tool_calls_str = vim.inspect(tool_calls)
    -- TODO if I keep this call to process_chunk, lets extract an underlying func for buffer_append or smth so its not confusing as this is not a chunk
    -- FYI if need to mod UI use vim.schedule (right now process_chunk does that)
    M.process_chunk(tool_calls_str)
end

function M.process_finish_reason(finish_reason)
    -- TODO long term do nothing OR set some visual indicator (i.e. spinner or pending request icon in statusline)
    -- FYI if need to mod UI use vim.schedule (right now process_chunk does that)
    M.process_chunk("finish_reason: " .. tostring(finish_reason))
end

function M.abort_last_request()
    backend.terminate(M.last_request)
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

    vim.keymap.set('n', '<leader>ao', M.open_response_window, { noremap = true })
    vim.keymap.set('n', '<leader>aa', M.abort_last_request, { noremap = true })
end

return M
