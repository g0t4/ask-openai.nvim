local M = {}

local function get_visual_selection()
    local _, start_line, start_col, _ = unpack(vim.fn.getpos("'<"))
    local _, end_line, end_col, _ = unpack(vim.fn.getpos("'>"))
    local lines = vim.fn.getline(start_line, end_line)

    if #lines == 0 then return "" end

    lines[#lines] = string.sub(lines[#lines], 1, end_col)
    lines[1] = string.sub(lines[1], start_col)

    return vim.fn.join(lines, "\n")
end


function M.send_to_ollama(user_prompt, code, file_name)
    local system_prompt = "You are a neovim AI plugin that rewrites code. "
        .. "Preserve indentation."
        .. "No explanations, no markdown blocks. No ``` nor ` surrounding your answer. "
        .. "Avoid pointless comments."

    local user_message = user_prompt
        .. ". Here is my code from " .. file_name
        .. ":\n\n" .. code

    local body = {
        messages = {
            { role = "system", content = system_prompt },
            { role = "user",   content = user_message },
        },
        model = "qwen2.5-coder:7b-instruct-q8_0",
        stream = false,
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
        local completion = parsed.choices[1].message.content
        if completion:sub(1, 3) == "```" and completion:sub(-3) == "```" then
            -- PRN maybe I should just ask for ``` around answer, would that increase likelihood of success anyways?
            completion = completion:sub(4, -4)
        end
        -- print(completion)
        return completion
    else
        print("Failed to get completion from Ollama API.")
        print(response)
    end
end

local function ask_and_send_to_ollama()
    local code = get_visual_selection()
    local user_prompt = vim.fn.input("Prompt: ")
    local file_name = vim.fn.expand("%:t")

    local completion = M.send_to_ollama(user_prompt, code, file_name)
    vim.fn.setreg("a", completion) -- backup in reg a

    -- TODO how about replace text directly?
    vim.cmd('normal! gv"ap')

    -- TODO fix new line issues, how can I gauge that sometimes it winds up removing new lines before/after?
    --    might be a thing to fix by looking at new lines originally
    --    and if there were new before/after ensure there's at least one new before and/or after AFTER replaced?
end

function M.setup()
    vim.api.nvim_create_user_command("AskRewrite", ask_and_send_to_ollama, { range = true })
    vim.api.nvim_set_keymap('v', '<Leader>rw', ':<C-u>AskRewrite<CR>', { noremap = true })
end

return M
