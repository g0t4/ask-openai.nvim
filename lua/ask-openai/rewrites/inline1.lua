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


function M.strip_md_from_completion(completion)
    local lines = vim.split(completion, "\n")

    local isFirstLineStartOfCodeBlock = lines[1]:match("^```(%S*)$")
    local isLastLineEndOfCodeBlock = lines[#lines]:match("^```")
    -- PRN warn if both indicators not true?

    if isLastLineEndOfCodeBlock then
        table.remove(lines, #lines)
    end
    if isFirstLineStartOfCodeBlock then
        table.remove(lines, 1)
    end
    return table.concat(lines, "\n")
end

function M.send_to_ollama(user_prompt, code, file_name)
    local system_prompt = "You are a neovim AI plugin that rewrites code. "
        .. "Preserve indentation."
        .. "No explanations, no markdown blocks. No ``` nor ` surrounding your answer. "
        .. "Avoid pointless comments. Do not remove existing code/comments unless the user asks you to."

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
        return M.strip_md_from_completion(parsed.choices[1].message.content)
    else
        error("Failed to get completion from Ollama API: " .. tostring(response))
    end
end

local function ensure_new_lines_around(code, response)
    -- this is a curtesy b/c its easy to select paragraphs with {} but it includes line before and after
    --    I can also pay attention to my selections

    -- TODO write tests of this going forward, don't manually test further

    -- ensure preserve blank line at start of selection (if present)
    local selected_lines = vim.split(code, "\n")
    local response_lines = vim.split(response, "\n")
    local selected_first_line = selected_lines[1]
    local response_first_line = response_lines[1]
    if selected_first_line:match("^%s*$")
        and not response_first_line:match("^%s*$")
    then
        -- print("Adding first line of code to completion")
        -- yup, add it verbatim so whitespace can still be there in that first line
        response = selected_first_line .. "\n" .. response
        -- resplit
        response_lines = vim.split(response, "\n")
    end

    -- ensure trailing new line is retained (if present)
    local selected_last_line = selected_lines[#selected_lines]
    local response_last_line = response_lines[#response_lines]
    if selected_last_line:match("^%s*$")
        and not response_last_line:match("^%s*$")
    then
        -- print("Adding trailing new line to completion")
        -- print("selected_last_line: '" .. selected_last_line .. "'")
        -- print("response_last_line: '" .. response_last_line .. "'")
        -- yup, add it verbatim so whitespace can still be there in that last line
        response = response .. "\n" .. selected_last_line .. "\n"
    end

    -- FYI could also look into running formatter on returned code in a way that can be undone by user if undesired but that fixes issues w/ indentation otherwise?

    return response
end

local function ask_and_send_to_ollama(opts)
    local original_text = get_visual_selection()
    if not original_text then
        error("No visual selection found.")
        return
    end

    local user_prompt = opts.args
    local file_name = vim.fn.expand("%:t")

    local rewritten_text = M.send_to_ollama(user_prompt, original_text, file_name)
    vim.fn.setreg("a", rewritten_text) -- set before to troubleshot if later fails

    rewritten_text = ensure_new_lines_around(original_text, rewritten_text)
    vim.fn.setreg("a", rewritten_text)

    -- Replace the selection with the new text
    vim.cmd('normal! gv"ap')
end

function M.setup()
    vim.api.nvim_create_user_command("AskRewrite", ask_and_send_to_ollama, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('v', '<Leader>rw', ':<C-u>AskRewrite ', { noremap = true })
end

return M
