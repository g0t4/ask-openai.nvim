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

local function ask_and_send_to_ollama(opts)
    local code, start_line, start_col, end_line, end_col = get_visual_selection()
    local user_prompt = opts.args
    local file_name = vim.fn.expand("%:t")
    print("start_line: " .. start_line)
    print("start_col: " .. start_col)
    print("end_line: " .. end_line)
    print("end_col: " .. end_col)

    local completion = M.send_to_ollama(user_prompt, code, file_name)
    vim.fn.setreg("a", completion)

    -- Check for newline before and after the selection
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local line_before = start_line - 1
    print("line before: '", lines[line_before], "'")
    print("line after: '", lines[end_line + 1], "'")

    local has_newline_before = start_line > 1 and (lines[line_before]:match("^%s*$") ~= nil)
    local has_newline_after = end_line < #lines and (lines[end_line + 1]:match("^%s*$") ~= nil)
    print("has_newline_before: " .. tostring(has_newline_before))
    print("has_newline_after: " .. tostring(has_newline_after))

    -- Replace the selection with the new text
    vim.cmd('normal! gv"ap')

    -- Re-check lines after paste
    local new_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    -- Ensure newline before
    if has_newline_before and not new_lines[line_before]:match("^%s*$") then
        -- vim.api.nvim_buf_set_lines(0, line_before, line_before, false, { "" })
    end

    -- FUX have to look at # lines inserted vs selected ARGH
    -- Ensure newline after
    -- if has_newline_after and (end_line >= #new_lines or not new_lines[end_line + 1]:match("^%s*$")) then
    --     vim.api.nvim_buf_set_lines(0, end_line + 1, end_line + 1, false, { "" })
    -- end
end

function M.setup()
    vim.api.nvim_create_user_command("AskRewrite", ask_and_send_to_ollama, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('v', '<Leader>rw', ':<C-u>AskRewrite ', { noremap = true })
end

return M
