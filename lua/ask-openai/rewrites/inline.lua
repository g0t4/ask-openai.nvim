local buffers = require("ask-openai.helpers.buffers")
local backend = require("ask-openai.questions.backends.chat_completions")
local log = require("ask-openai.prediction.logger").predictions() -- TODO rename to just ask-openai logger in general
local uv = vim.uv
local M = {}

-- Set up a highlight group for the extmarks
vim.api.nvim_command("highlight default AskRewrite guifg=#00ff00 ctermfg=green")

-- Initialize selection position variables at module level
M.start_line = nil
M.start_col = nil
M.end_line = nil
M.end_col = nil
M.original_text = nil
M.current_text = ""
M.namespace_id = vim.api.nvim_create_namespace("ask-openai-rewrites")
M.extmark_id = nil

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

local function split_lines_to_table(text)
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    return lines
end

function M.handle_stream_chunk(chunk)
    if not chunk then return end

    -- Accumulate chunks
    M.current_text = M.current_text .. chunk

    local current_md_stripped = M.strip_md_from_completion(M.current_text)
    local current_polished = ensure_new_lines_around(M.original_text, current_md_stripped)

    -- Update the extmark with the current accumulated text
    vim.schedule(function()
        -- Clear previous extmark
        vim.api.nvim_buf_clear_namespace(0, M.namespace_id, 0, -1)

        -- Split into lines for extmark display
        local lines = split_lines_to_table(current_polished)
        if #lines == 0 then return end

        local first_line = { { table.remove(lines, 1), "AskRewrite" } }

        -- Format remaining lines for virt_lines
        local virt_lines = {}
        for _, line in ipairs(lines) do
            table.insert(virt_lines, { { line, "AskRewrite" } })
        end

        -- Set extmark at the beginning of the selection
        M.extmark_id = vim.api.nvim_buf_set_extmark(
            0, -- Current buffer
            M.namespace_id,
            M.start_line - 1, -- Zero-indexed
            M.start_col - 1, -- Zero-indexed
            {
                virt_text = first_line,
                virt_lines = virt_lines,
                virt_text_pos = "overlay",
                hl_mode = "combine"
            }
        )
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

function M.accept_rewrite()
    vim.schedule(function()
        -- Get the current polished text
        local current_md_stripped = M.strip_md_from_completion(M.current_text)
        local current_polished = ensure_new_lines_around(M.original_text, current_md_stripped)
        local lines = split_lines_to_table(current_polished)

        local use_start_line = M.start_line - 1
        local use_end_line = M.end_line - 1
        local use_start_col = M.start_col - 1
        local use_end_col = M.end_col - 1

        log:info("using positions:\n  start_line: " .. use_start_line .. "\n  end_line: " .. use_end_line
            .. "\n  start_col: " .. use_start_col .. "\n  end_col: " .. use_end_col)



        -- Replace the selected text with the generated content
        vim.api.nvim_buf_set_text(
            0, -- Current buffer
            use_start_line, -- Zero-indexed
            use_start_col, -- Zero-indexed
            use_end_line, -- Zero-indexed
            use_end_col, -- Zero-indexed?
            lines
        )

        -- Clear the extmark
        vim.api.nvim_buf_clear_namespace(0, M.namespace_id, 0, -1)

        -- Reset the module state
        M.current_text = ""
        M.extmark_id = nil

        -- Log acceptance
        log:info("Rewrite accepted and inserted into buffer", vim.log.levels.INFO)
    end)
end

function M.cancel_rewrite()
    vim.schedule(function()
        -- Clear the extmark
        vim.api.nvim_buf_clear_namespace(0, M.namespace_id, 0, -1)

        -- Reset the module state
        M.current_text = ""
        M.extmark_id = nil

        -- Log cancellation
        log:info("Rewrite cancelled", vim.log.levels.INFO)
    end)
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

    -- Clear any extmarks
    vim.api.nvim_buf_clear_namespace(0, M.namespace_id, 0, -1)
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

        -- Log completion
        log:info("Rewrite generation complete", vim.log.levels.INFO)
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
    local selection = buffers.get_visual_selection()
    if not selection.original_text then
        error("No visual selection found.")
        return
    end

    local user_prompt = opts.args
    local file_name = vim.fn.expand("%:t")

    -- Store selection details for later use
    M.start_line = selection.start_line
    M.start_col = selection.start_col
    M.end_line = selection.end_line
    M.end_col = selection.end_col
    M.original_text = selection.original_text
    M.current_text = ""
    log:info(string.format(
        "Original text: %s\nstart_line: %d\nstart_col: %d\nend_line: %d\nend_col: %d",
        selection.original_text, selection.start_line, selection.start_col, selection.end_line, selection.end_col
    ))


    M.stream_from_ollama(user_prompt, selection.original_text, file_name)
end

function M.setup()
    -- Create commands and keymaps for the rewrite functionality
    vim.api.nvim_create_user_command("AskRewrite", ask_and_stream_from_ollama, { range = true, nargs = 1 })
    vim.api.nvim_set_keymap('v', '<Leader>rw', ':<C-u>AskRewrite ', { noremap = true })

    -- Add a command to abort the stream if needed
    vim.api.nvim_create_user_command("AskRewriteAbort", M.abort_if_still_responding, {})
    vim.api.nvim_set_keymap('n', '<Leader>ra', ':AskRewriteAbort<CR>', { noremap = true })

    -- Add commands and keymaps for accepting or cancelling the rewrite
    vim.api.nvim_create_user_command("AskRewriteAccept", M.accept_rewrite, {})
    vim.api.nvim_set_keymap('n', '<Leader>ry', ':AskRewriteAccept<CR>', { noremap = true })

    vim.api.nvim_create_user_command("AskRewriteCancel", M.cancel_rewrite, {})
    vim.api.nvim_set_keymap('n', '<Leader>rn', ':AskRewriteCancel<CR>', { noremap = true })
end

return M
