local buffers = require("ask-openai.helpers.buffers")
local backend = require("ask-openai.questions.backends.chat_completions")
local log = require("ask-openai.prediction.logger").predictions() -- TODO rename to just ask-openai logger in general
local uv = vim.uv
local M = {}

-- Set up a highlight group for the extmarks
local hlgroup = "AskRewrite"
vim.api.nvim_command("highlight default " .. hlgroup .. " guifg=#ccffcc ctermfg=green")

-- Initialize selection position variables at module level
M.selection = nil
M.accumulated_chunks = ""
M.namespace_id = vim.api.nvim_create_namespace("ask-openai-rewrites")
M.extmark_id = nil

function M.strip_md_from_completion(lines)
    local isFirstLineStartOfCodeBlock = lines[1]:match("^```(%S*)$")
    local isLastLineEndOfCodeBlock = lines[#lines]:match("^```")

    if isLastLineEndOfCodeBlock then
        table.remove(lines, #lines)
    end
    if isFirstLineStartOfCodeBlock then
        table.remove(lines, 1)
    end

    return lines
end

local function split_text_into_lines(text)
    -- preserve empty lines too
    return vim.split(text, "\n")
end

function M.handle_stream_chunk(chunk)
    if not chunk then return end

    M.accumulated_chunks = M.accumulated_chunks .. chunk

    local lines = split_text_into_lines(M.accumulated_chunks)
    lines = M.strip_md_from_completion(lines)
    lines = ensure_new_lines_around(M.selection.original_text, lines)

    vim.schedule(function()
        -- Clear previous extmark
        vim.api.nvim_buf_clear_namespace(0, M.namespace_id, 0, -1)

        if #lines == 0 then return end

        local first_line = { { table.remove(lines, 1), hlgroup } }

        -- Format remaining lines for virt_lines
        local virt_lines = {}
        for _, line in ipairs(lines) do
            table.insert(virt_lines, { { line, hlgroup } })
        end

        -- Set extmark at the beginning of the selection
        M.extmark_id = vim.api.nvim_buf_set_extmark(
            0, -- Current buffer
            M.namespace_id,
            M.selection.start_line_1based - 1, -- Zero-indexed
            M.selection.start_col_1based - 1, -- Zero-indexed
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
function ensure_new_lines_around(code, response_lines)
    -- * Ensure preserve blank line at start of selection (if present)
    local selected_lines = split_text_into_lines(code)
    local selected_first_line = selected_lines[1]
    local response_first_line = response_lines[1]

    local selection_starts_with_newline = selected_first_line:match("^%s*$")
    local response_starts_with_newline =
        response_first_line == nil or response_first_line:match("^%s*$")

    if selection_starts_with_newline and not response_starts_with_newline
    then
        table.insert(response_lines, 1, selected_first_line) -- add back the blank line at start
    end

    -- * Ensure trailing new line is retained (if present)
    local selected_last_line = selected_lines[#selected_lines]
    local response_last_line = response_lines[#response_lines]
    local selection_ends_with_newline = selected_last_line:match("^%s*$")
    local response_ends_with_newline =
        response_last_line == nil or response_last_line:match("^%s*$")

    if selection_ends_with_newline and not response_ends_with_newline then
        -- response = response .. "\n" .. selected_last_line .. "\n"
        -- TODO do I need a new line appeneded too?
        table.insert(response_lines, selected_last_line)
    end

    return response_lines
end

function M.accept_rewrite()
    vim.schedule(function()
        local lines = split_text_into_lines(M.accumulated_chunks)
        lines = M.strip_md_from_completion(lines)
        lines = ensure_new_lines_around(M.selection.original_text, lines)

        local use_start_line_0based = M.selection.start_line_1based - 1
        local use_end_line_0based = M.selection.end_line_1based - 1
        local use_start_col_0based = M.selection.start_col_1based - 1
        local use_end_col_0based = M.selection.end_col_1based - 1

        log:info("nvim_buf_set_text: 0-based "
            .. "start(line=" .. use_start_line_0based
            .. ",col=" .. use_start_col_0based
            .. ") end(line=" .. use_end_line_0based
            .. ",col=" .. use_end_col_0based
            .. ")")

        -- Dump selection in 0based for debugging too
        M.selection:log_info(true)

        -- Relpace the selected text with the generated content
        vim.api.nvim_buf_set_text(
            0, -- Current buffer
            use_start_line_0based, -- Zero-indexed
            use_start_col_0based, -- Zero-indexed
            use_end_line_0based, -- Zero-indexed, end-inclusive line/row
            use_end_col_0based, -- Zero-indexed, end-exclusive column
            lines
        )

        -- Clear the extmark
        vim.api.nvim_buf_clear_namespace(0, M.namespace_id, 0, -1)

        -- Reset the module state
        M.accumulated_chunks = ""
        M.extmark_id = nil

        -- Log acceptance
        log:info("Rewrite accepted and inserted into buffer")
    end)
end

function M.cancel_rewrite()
    vim.schedule(function()
        -- Clear the extmark
        vim.api.nvim_buf_clear_namespace(0, M.namespace_id, 0, -1)

        -- Reset the module state
        M.accumulated_chunks = ""
        M.extmark_id = nil

        -- Log cancellation
        log:info("Rewrite cancelled")
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
            log:error("Error in curl command: " .. tostring(code) .. " Signal: " .. tostring(signal))
        end
        stdout:close()
        stderr:close()

        -- Clear out refs
        M.handle = nil
        M.pid = nil

        -- Log completion
        log:info("Rewrite generation complete")
    end

    M.abort_if_still_responding()

    M.handle, M.pid = uv.spawn(options.command, {
        args = options.args,
        stdio = { nil, stdout, stderr },
    }, options.on_exit)

    options.on_stdout = function(err, data)
        if err then
            log:error("Error reading stdout: " .. tostring(err))
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
                    log:info("Rewrite complete")
                end
            end)
        end
    end
    uv.read_start(stdout, options.on_stdout)

    options.on_stderr = function(err, data)
        if err or (data and #data > 0) then
            log:error("Error from curl: " .. tostring(data or err))
        end
    end
    uv.read_start(stderr, options.on_stderr)
end

local function ask_and_stream_from_ollama(opts)
    -- TODO add an arg or separate command that includes surrounding context (and marks what is selected for rewrite => kinda like Zed does)
    -- TODO add a mechanism to capture requests so I can look into prompt updates/fine-tuning/DPO/etc or just test cases
    -- TODO add a feedback like mechanism to take notes about the response (i.e. if I like it or not)
    -- PRN capture relevant symbols (i.e. look at variables in scope of the selection and fetch symbols from CoC or just whole file?)
    --    and/or past edits might be sufficient quite often

    -- TODO end column calc is off by one

    local selection = buffers.get_visual_selection()
    if selection:is_empty() then
        error("No visual selection found.")
        return
    end

    local user_prompt = opts.args
    local file_name = vim.fn.expand("%:t")

    -- Store selection details for later use
    M.selection = selection
    M.accumulated_chunks = ""
    selection:log_info()

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

    -- dump helpers while building this tooling - [a]sk [d]ump last [s]election
    vim.api.nvim_create_user_command("AskDumpLastSelection", buffers.dump_last_seletion, {})
    vim.api.nvim_set_keymap('n', '<Leader>ads', ':AskDumpLastSelection<CR>', { noremap = true })
    vim.api.nvim_set_keymap('v', '<Leader>ads', ':<C-u>AskDumpLastSelection<CR>', { noremap = true })
    -- FYI see notes in M.get_visual_selection about you don't want a lua func handler that calls dump
    -- also prints don't popup if they originated in a lua handler, whereas they do with a vim command
    --   thus w/ a cmd I get to see the vim.inspect(selection) with a pprint json like view of fields
end

return M
