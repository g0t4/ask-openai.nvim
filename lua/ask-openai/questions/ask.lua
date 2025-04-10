local buffers = require("ask-openai.helpers.buffers")
local log = require("ask-openai.prediction.logger").predictions() -- TODO rename to just ask-openai logger in general
local middleend = require("ask-openai.backends.middleend")
local F = {}

function F.send_question(user_prompt, code, file_name)
    local system_prompt = "You are a neovim AI plugin that answers questions."
        .. " Please respond with markdown formatted text"

    local user_message = user_prompt
    if code then
        user_message = user_message
            .. ". Here is my code from " .. file_name
            .. ":\n\n" .. code
    end

    -- TODO USE model specific params passed and use for body (merge)
    --    make this a step before calling this method or a separate aspect so it can be reused in rewrites and other usage (i.e. agent tool eventually)
    -- i.e. agentica's https://huggingface.co/agentica-org/DeepCoder-14B-Preview#usage-recommendations
    local agentica_params = {
        -- TODO for agentic... and all reasoning models, I need to split apart the <think> chunk when its done and display spearately, right?
        messages = {
            -- TODO if agentica recommends no system prompt.. would it make more sense to just use legacy completions for that use case oai_completions?
            { role = "user", content = system_prompt .. "\n" .. user_message },
        },
        -- Avoid adding a system prompt; all instructions should be contained within the user prompt.
        model = "agentica-org/DeepCoder-1.5B-Preview",
        -- TODO 14B-Preview quantized variant
        temperature = 0.6,
        top_p = 0.95,
        -- max_tokens set to at least 64000
        max_tokens = 64000,
        -- TODO can I just not set max_tokens too?
    }

    local ollama_qwen_params = {
        messages = {
            { role = "system", content = system_prompt },
            { role = "user",   content = user_message },
        },

        -- model = "qwen2.5-coder:14b-instruct-q8_0", -- btw -base- does terrible here :)
        model = "gemma3:12b-it-q8_0", -- btw -base- does terrible here :)
        -- temperature = 0.2, -- TODO what temp?
        -- PRN limit num_predict?
        options = {
            -- TODO! do I need num_ctx, I can't recall why I set this for predictions?
            num_ctx = 8192,
        }
    }

    local body = agentica_params
    body.stream = true

    local json = vim.fn.json_encode(body)
    -- "http://ollama:11434/v1/chat/completions", -- TODO pass in api base_url (via config)
    local base_url = "http://build21:8000"

    F.last_request = middleend.curl_for(json, base_url, F)
end

local function ask_question_about(opts)
    local selection = buffers.get_visual_selection()
    if selection:is_empty() then
        error("No visual selection found.")
        return
    end

    local user_prompt = opts.args
    local file_name = vim.fn.expand("%:t")

    F.open_response_window()
    F.send_question(user_prompt, selection.original_text, file_name)
end

local function ask_question(opts)
    local user_prompt = opts.args
    F.open_response_window()
    F.send_question(user_prompt)
end

function F.abort_and_close()
    F.abort_last_request()
    vim.cmd(":q", { buffer = F.bufnr })
end

function F.open_response_window()
    local name = 'Question Response'

    if F.bufnr == nil then
        F.bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(F.bufnr, name)

        -- stop generation, if still wanna look at it w/o closing the window
        vim.keymap.set("n", "<Esc>", F.abort_last_request, { buffer = F.bufnr, nowait = true })
        vim.keymap.set("n", "<F8>", F.abort_and_close, { buffer = F.bufnr }) -- I already use this globally to close a window (:q) ... so just add stop to it
        -- OR, should I let it keep completing in background and then I can come back when its done? for async?
    end

    vim.api.nvim_buf_set_lines(F.bufnr, 0, -1, false, {}) -- clear the buffer, is there an easier way?

    local screen_lines = vim.api.nvim_get_option_value('lines', {})
    local screen_columns = vim.api.nvim_get_option_value('columns', {})
    local win_height = math.ceil(0.5 * screen_lines)
    local win_width = math.ceil(0.5 * screen_columns)
    local top_is_at_row = screen_lines / 2 - win_height / 2
    local left_is_at_col = screen_columns / 2 - win_width / 2
    local _winid = vim.api.nvim_open_win(F.bufnr, true, {
        relative = 'editor',
        width = win_width,
        height = win_height,
        row = top_is_at_row,
        col = left_is_at_col,
        style = 'minimal',
        border = 'single'
    })
    -- set FileType after creating window, otherwise the default wrap option (vim.o.wrap) will override any ftplugin mods to wrap (and the same for other window-local options like wrap)
    vim.api.nvim_set_option_value('filetype', 'markdown', { buf = F.bufnr })
end

function F.add_to_response_window(text)
    local count_of_lines = vim.api.nvim_buf_line_count(F.bufnr)
    local last_line = vim.api.nvim_buf_get_lines(F.bufnr, count_of_lines - 1, count_of_lines, false)[1]
    local replace_lines = vim.split(last_line .. text, "\n")
    vim.api.nvim_buf_set_lines(F.bufnr, count_of_lines - 1, count_of_lines, false, replace_lines)
end

function F.abort_last_request()
    middleend.terminate(F.last_request)
end

function F.setup()
    -- once again, pass question in command line for now... b/c then I can use cmd history to ask again or modify question easily
    --  if I move to a float window, I'll want to add history there then which I can handle later when this falls apart
    vim.api.nvim_create_user_command("AskQuestion", ask_question, { range = true, nargs = 1 })
    vim.api.nvim_create_user_command("AskQuestionAbout", ask_question_about, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('v', '<Leader>aq', ':<C-u>AskQuestionAbout ', { noremap = true })
    vim.api.nvim_set_keymap('n', '<Leader>aq', ':AskQuestion ', { noremap = true })
    vim.keymap.set('n', '<leader>ao', F.open_response_window, { noremap = true })
    vim.keymap.set('n', '<leader>aa', F.abort_last_request, { noremap = true })
end

return F
