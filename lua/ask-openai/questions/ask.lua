local buffers = require("ask-openai.helpers.buffers")
local log = require("ask-openai.prediction.logger").predictions()
-- local backend = require("ask-openai.backends.oai_chat")
local backend = require("ask-openai.backends.oai_completions")
local agentica = require("ask-openai.backends.models.agentica")

local M = {}

function M.send_question(user_prompt, code, file_name)
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
        --   review start logs for n_ctx and during completion it warns if truncated prompt
        --      does it return that warning to curl call?
    }

    local qwen_legacy_body = {
        model = "qwen2.5-coder:7b-instruct-q8_0", -- btw -base- does terrible here :)
        prompt = system_prompt .. "\n" .. user_message,
        -- todo temp etc
    }

    -- /v1/chat/completions
    -- local body = agentica.DeepCoder.build_chat_body(system_prompt, user_message)
    -- local body = qwen_chat_completions

    -- /v1/completions
    local body = qwen_legacy_body

    -- vllm or ollama:
    local base_url = "http://ollama:11434"
    -- local base_url = "http://build21:8000"

    M.last_request = backend.curl_for(body, base_url, M)
end

local function ask_question_about(opts)
    local selection = buffers.get_visual_selection()
    if selection:is_empty() then
        error("No visual selection found.")
        return
    end

    local user_prompt = opts.args
    local file_name = vim.fn.expand("%:t")

    M.open_response_window()
    M.send_question(user_prompt, selection.original_text, file_name)
end

local function ask_question(opts)
    local user_prompt = opts.args
    M.open_response_window()
    M.send_question(user_prompt)
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
--
--  TODO should I detect some failures like Failed to connect in on_stderr? and print/pass the message back in that case?
--
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
    local count_of_lines = vim.api.nvim_buf_line_count(M.bufnr)
    local last_line = vim.api.nvim_buf_get_lines(M.bufnr, count_of_lines - 1, count_of_lines, false)[1]
    local replace_lines = vim.split(last_line .. text, "\n")
    vim.api.nvim_buf_set_lines(M.bufnr, count_of_lines - 1, count_of_lines, false, replace_lines)
end

function M.abort_last_request()
    backend.terminate(M.last_request)
end

function M.setup()
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
