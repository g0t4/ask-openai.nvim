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

    local parsed = vim.fn.json_decode(response)

    if parsed and parsed.choices and #parsed.choices > 0 then
        return parsed.choices[1].message.content
    else
        error("Failed to get completion from Ollama API: " .. tostring(response))
    end
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
