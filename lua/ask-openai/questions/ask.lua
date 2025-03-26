local M = {}

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
        stream = false, -- TODO stream response back is a MUST!, but will likely require a popup window
        temperature = 0.2
    }

    local json = vim.fn.json_encode(body)
    local response = vim.fn.system({
        "curl", "-s", "-X", "POST", "http://ollama:11434/v1/chat/completions",
        "-H", "Content-Type: application/json",
        "-d", json
    })

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    options.on_exit = function(code, signal)
        if code ~= 0 then
            log:error("spawn - non-zero exit code:", code, "Signal:", signal)
        end
        stdout:close()
        stderr:close()
    end

    M.handle, M.pid = uv.spawn(options.command, {
        args = options.args,
        stdio = { nil, stdout, stderr },
    }, options.on_exit)

    options.on_stdout = function(err, data)
        -- log:trace("on_stdout chunk: ", data)
        if err then
            log:warn("on_stdout error: ", err)
            this_prediction:mark_generation_failed()
            return
        end
        if data then
            vim.schedule(function()
                local chunk, generation_done = backend.process_sse(data)
                if chunk then
                    this_prediction:add_chunk_to_prediction(chunk)
                end
                if generation_done then
                    this_prediction:mark_generation_finished()
                end
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

    local response = M.send_question(user_prompt, code, file_name)
    print(response)
end

local function ask_question(opts)
    local user_prompt = opts.args
    local response = M.send_question(user_prompt)
    M.show_response(response)
end

function M.cancel_current_prediction()
    -- TODO!
    local this_prediction = M.current_prediction
    if not this_prediction then
        return
    end
    M.current_prediction = nil
    this_prediction:mark_as_abandoned()

    vim.schedule(function()
        this_prediction:clear_extmarks()
    end)

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

function M.show_response(response)
    -- TODO request markdown as response format... and highlight that as markdown in a buffer
    local name = 'Question Response'

    if M.bufnr == nil then
        M.bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(M.bufnr, name)
    end

    local lines = vim.split(response, "\n")
    vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, lines)

    local screen_lines = vim.api.nvim_get_option_value('lines', {})
    local screen_columns = vim.api.nvim_get_option_value('columns', {})
    -- TODO revisit sizing window, could I set the size after the buffer is loaded and somehow allow it to resize bigger if it would fit into a max size?
    local min_height = 0.5 * screen_lines
    local min_width = 0.5 * screen_columns
    local max_height = 0.9 * screen_lines
    local max_width = 0.9 * screen_columns
    -- print("min_height", min_height)
    -- print("max_height", max_height)
    -- print("#lines", #lines)
    -- print("screen_lines", screen_lines)
    local win_height = math.floor(math.min(max_height, math.max(min_height, #lines))) -- TODO need to estimate wrapping text
    local win_width = min_width
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

function M.setup()
    -- once again, pass question in command line for now... b/c then I can use cmd history to ask again or modify question easily
    --  if I move to a float window, I'll want to add history there then which I can handle later when this falls apart
    vim.api.nvim_create_user_command("AskQuestion", ask_question, { range = true, nargs = 1 })
    vim.api.nvim_create_user_command("AskQuestionAbout", ask_question_about, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('v', '<Leader>aq', ':<C-u>AskQuestionAbout ', { noremap = true })
    vim.api.nvim_set_keymap('n', '<Leader>aq', ':AskQuestion ', { noremap = true })
end

return M
