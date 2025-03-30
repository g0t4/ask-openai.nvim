local uv = vim.uv
local M = {}
local log = require("ask-openai.prediction.logger").predictions() -- TODO rename to just ask-openai logger in general
local backend = require("ask-openai.questions.backends.chat_completions")

local function get_visual_selection()
    local _, start_line, start_col, _ = unpack(vim.fn.getpos("'<"))
    local _, end_line, end_col, _ = unpack(vim.fn.getpos("'>"))
    local lines = vim.fn.getline(start_line, end_line)

    -- in visual line mode =>
    --   start_col = 0 (can be but not in my test of it, it was 1)
    --   end_col = v:maxcol
    -- FOR NOW lets just map those:
    if end_col == vim.v.maxcol then
        -- TODO ? map to end column of same line instead of wrap down a line, this s/b fine for now though
        end_line = end_line + 1
        end_col = 1
        -- TODO handle edge case (last line)
        -- TODO why wasn't this an issue in inline1.lua?
    end

    if #lines == 0 then return "" end

    lines[#lines] = string.sub(lines[#lines], 1, end_col)
    lines[1] = string.sub(lines[1], start_col)

    return vim.fn.join(lines, "\n"), start_line, start_col, end_line, end_col
end

-- Initialize selection position variables at module level
M.start_line = nil
M.start_col = nil
M.end_line = nil
M.end_col = nil
M.original_text = nil
M.current_text = ""

function M.strip_md_from_completion(completion)
    local lines = vim.split(completion, "\n")

    local isFirstLineStartOfCodeBlock = lines[1]:match("^```(%S*)$")
    local isLastLineEndOfCodeBlock = lines[#lines]:match("^```")

    if isLastLineEndOfCodeBlock then
        table.remove(lines, #lines)
    end
    if isFirstLineStartOfCodeBlock then
        table.remove(lines, 1)
    end
    return table.concat(lines, "\n")
end

function M.handle_stream_chunk(chunk)
    if not chunk then return end

    -- Strip markdown if needed
    -- local cleaned_chunk = M.strip_md_from_completion(chunk)

    -- Accumulate chunks (good can use this for new lines around, in real time!
    M.current_text = M.current_text .. chunk

    -- Process newlines and ensure proper formatting
    local formatted_text = ensure_new_lines_around(M.original_text, M.current_text)

    -- Update the document with the current accumulated text
    vim.schedule(function()
        -- Replace the selection with the current text
        vim.api.nvim_buf_set_text(
            0, -- Current buffer
            M.start_line - 1, -- Zero-indexed
            M.start_col - 1, -- Zero-indexed
            M.end_line - 1, -- Zero-indexed
            M.end_col, -- End column
            vim.split(formatted_text, "\n")
        )

        -- this is where extmark is gonna probably be easier b/c can just clear it and keep constant row/columns
        -- Update end line/col based on new text
        local new_lines = vim.split(formatted_text, "\n")
        M.end_line = M.start_line + #new_lines - 1
        if #new_lines > 1 then
            M.end_col = #new_lines[#new_lines]
        else
            M.end_col = M.start_col - 1 + #formatted_text
        end
    end)
end

-- TODO move above and make local again
function ensure_new_lines_around(code, response)
    -- Ensure preserve blank line at start of selection (if present)
    local selected_lines = vim.split(code, "\n")
    local response_lines = vim.split(response, "\n")
    local selected_first_line = selected_lines[1]
    local response_first_line = response_lines[1]
    if selected_first_line:match("^%s*$")
        and not response_first_line:match("^%s*$")
    then
        response = selected_first_line .. "\n" .. response
        response_lines = vim.split(response, "\n")
    end

    -- Ensure trailing new line is retained (if present)
    local selected_last_line = selected_lines[#selected_lines]
    local response_last_line = response_lines[#response_lines]
    if selected_last_line:match("^%s*$")
        and not response_last_line:match("^%s*$")
    then
        response = response .. "\n" .. selected_last_line .. "\n"
    end

    return response
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
        handle:kill("sigterm")
        handle:close()
    end
end

function M.stream_from_ollama(user_prompt, code, file_name)
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
        stream = true,
        temperature = 0.2,
        -- TODO do I need num_ctx (can't recall why I set it - check predicitons code)
        -- options = {
        --     num_ctx = 8192
        -- }
    }

    local json = vim.fn.json_encode(body)

    local options = {
        command = "curl",
        args = {
            "-fsSL",
            "--no-buffer", -- Prevent curl from buffering output
            "-X", "POST",
            "http://ollama:11434/v1/chat/completions",
            "-H", "Content-Type: application/json",
            "-d", json
        },
    }

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    options.on_exit = function(code, signal)
        if code ~= 0 then
            log:error("Error in curl command: " .. tostring(code) .. " Signal: " .. tostring(signal), vim.log.levels.ERROR)
        end
        stdout:close()
        stderr:close()

        -- Clear out refs
        M.handle = nil
        M.pid = nil
    end

    M.abort_if_still_responding()

    M.handle, M.pid = uv.spawn(options.command, {
        args = options.args,
        stdio = { nil, stdout, stderr },
    }, options.on_exit)

    options.on_stdout = function(err, data)
        if err then
            log:error("Error reading stdout: " .. tostring(err), vim.log.levels.WARN)
            return
        end
        if data then
            vim.schedule(function()
                local chunk, generation_done = backend.process_sse(data)
                if chunk then
                    M.handle_stream_chunk(chunk)
                end
                if generation_done then
                    -- Optionally do something when generation is complete
                    log:info("Rewrite complete", vim.log.levels.INFO)
                end
            end)
        end
    end
    uv.read_start(stdout, options.on_stdout)

    options.on_stderr = function(err, data)
        if err or (data and #data > 0) then
            log:error("Error from curl: " .. tostring(data or err), vim.log.levels.WARN)
        end
    end
    uv.read_start(stderr, options.on_stderr)
end

local function ask_and_stream_from_ollama(opts)
    local original_text, start_line, start_col, end_line, end_col = get_visual_selection()
    if not original_text then
        error("No visual selection found.")
        return
    end

    local user_prompt = opts.args
    local file_name = vim.fn.expand("%:t")

    -- Store selection details for later use
    M.start_line = start_line
    M.start_col = start_col
    M.end_line = end_line
    M.end_col = end_col
    M.original_text = original_text
    M.current_text = ""
    log:info(string.format(
        "Original text: %s\nstart_line: %d\nstart_col: %d\nend_line: %d\nend_col: %d",
        original_text, start_line, start_col, end_line, end_col
    ), vim.log.levels.INFO)

    M.stream_from_ollama(user_prompt, original_text, file_name)
end

function M.setup()
    -- TODO remove v1 AskRewrite and rename this when done
    vim.api.nvim_create_user_command("AskRewrite2", ask_and_stream_from_ollama, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('v', '<Leader>r2', ':<C-u>AskRewrite2 ', { noremap = true })

    -- Add a command to abort the stream if needed
    vim.api.nvim_create_user_command("AskRewriteAbort", M.abort_if_still_responding, {})
    vim.api.nvim_set_keymap('n', '<Leader>ra', ':AskRewriteAbort<CR>', { noremap = true })
end

return M
