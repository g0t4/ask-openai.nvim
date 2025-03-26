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
    -- TODO request markdown as response format... and highlight that as markdown in a buffer
    print(response)
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
