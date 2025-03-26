local uv = vim.uv
local M = {}
local log = require("ask-openai.prediction.logger").predictions() -- TODO rename to just ask-openai logger in general

local backend = require("ask-openai.questions.backends.chat_completions")

local function get_visual_selection()
    local _, start_line, start_col, _ = unpack(vim.fn.getpos("'<"))
    local _, end_line, end_col, _ = unpack(vim.fn.getpos("'>"))
    local lines = vim.fn.getline(start_line, end_line)

    if #lines == 0 then return "" end

    lines[#lines] = string.sub(lines[#lines], 1, end_col)
    lines[1] = string.sub(lines[1], start_col)

    return vim.fn.join(lines, "\n"), start_line, start_col, end_line, end_col
end

function M.send_question(user_prompt, code, file_name)
    local system_prompt = "You are a neovim AI plugin that answers questions."
        .. " Please respond with markdown formatted text"

    local user_message = user_prompt
    if code then
        user_message = user_message
            .. ". Here is the relevant code from" .. file_name
            .. ":\n\n" .. code
    end

    local body = {
        messages = {
            { role = "system", content = system_prompt },
            { role = "user",   content = user_message },
        },
        model = "qwen2.5-coder:7b-instruct-q8_0",
        stream = true,
        temperature = 0.2, -- TODO what temp?
        -- PRN limit num_predict?
        options = {
            -- TODO! do I need num_ctx, I can't recall why I set this for predictions?
            num_ctx = 8192,
        }
    }

    local json = vim.fn.json_encode(body)

    local options = {
        command = "curl",
        args = {
            "-fsSL",
            "--no-buffer", -- curl seems to be the culprit... w/o this it batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            "http://ollama:11434/v1/chat/completions", -- TODO pass in api base_url (via config)
            "-H", "Content-Type: application/json",
            "-d", json
        },
    }

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    options.on_exit = function(code, signal)
        if code ~= 0 then
            log:error("spawn - non-zero exit code:", code, "Signal:", signal)
        end
        stdout:close()
        stderr:close()

        -- clear out refs
        M.handle = nil
        M.pid = nil
    end

    M.abort_if_still_responding()

    M.handle, M.pid = uv.spawn(options.command, {
        args = options.args,
        stdio = { nil, stdout, stderr },
    }, options.on_exit)

    options.on_stdout = function(err, data)
        -- log:trace("on_stdout chunk: ", data)
        if err then
            log:warn("on_stdout error: ", err)
            return
        end
        if data then
            vim.schedule(function()
                local chunk, generation_done = backend.process_sse(data)
                if chunk then
                    M.add_to_response_window(chunk)
                end
                -- PRN anything on done?
                -- if generation_done then
                --     this_prediction:mark_generation_finished()
                -- end
            end)
        end
    end
    uv.read_start(stdout, options.on_stdout)

    options.on_stderr = function(err, data)
        log:warn("on_stderr chunk: ", data)
        if err then
            log:warn("on_stderr error: ", err)
        end
    end
    uv.read_start(stderr, options.on_stderr)
end

local function ask_question_about(opts)
    local code = get_visual_selection()
    if not code then
        error("No visual selection found.")
        return
    end

    local user_prompt = opts.args
    local file_name = vim.fn.expand("%:t")

    M.open_response_window()
    M.send_question(user_prompt, code, file_name)
end

local function ask_question(opts)
    local user_prompt = opts.args
    M.open_response_window()
    M.send_question(user_prompt)
end

function M.abort_if_still_responding()
    if M.handle == nil then
        return
    end

    local handle = M.handle
    local pid = M.pid
    M.handle = nil
    M.pid = nil
    if handle ~= nil and not handle:is_closing() then
        log:trace("Terminating process, pid: ", pid)

        handle:kill("sigterm")
        handle:close()
        -- FYI ollama should show that connection closed/aborted
    end
end

function M.open_response_window()
    local name = 'Question Response'

    -- TODO bind closing the popup window to stopping the response?

    if M.bufnr == nil then
        M.bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(M.bufnr, name)
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

function M.add_to_response_window(text)
    local count_of_lines = vim.api.nvim_buf_line_count(M.bufnr)
    local last_line = vim.api.nvim_buf_get_lines(M.bufnr, count_of_lines - 1, count_of_lines, false)[1]
    local replace_lines = vim.split(last_line .. text, "\n")
    vim.api.nvim_buf_set_lines(M.bufnr, count_of_lines - 1, count_of_lines, false, replace_lines)
end

function M.setup()
    -- once again, pass question in command line for now... b/c then I can use cmd history to ask again or modify question easily
    --  if I move to a float window, I'll want to add history there then which I can handle later when this falls apart
    vim.api.nvim_create_user_command("AskQuestion", ask_question, { range = true, nargs = 1 })
    vim.api.nvim_create_user_command("AskQuestionAbout", ask_question_about, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('v', '<Leader>aq', ':<C-u>AskQuestionAbout ', { noremap = true })
    vim.api.nvim_set_keymap('n', '<Leader>aq', ':AskQuestion ', { noremap = true })
    vim.keymap.set('n', '<leader>ao', M.open_response_window, { noremap = true })
    vim.keymap.set('n', '<leader>aa', M.abort_if_still_responding, { noremap = true })
end

return M
