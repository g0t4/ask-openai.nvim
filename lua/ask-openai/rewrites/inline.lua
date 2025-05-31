local buffers = require("ask-openai.helpers.buffers")
local backend = require("ask-openai.backends.oai_chat")
-- local backend = require("ask-openai.backends.oai_completions")
local log = require("ask-openai.prediction.logger").predictions()
local agentica = require("ask-openai.backends.models.agentica")
local text_helpers = require("ask-openai.helpers.text")
local thinking = require("ask-openai.rewrites.thinking")
local Selection = require("ask-openai.helpers.selection")

local M = {}

-- Set up a highlight group for the extmarks
local hlgroup = "AskRewrite"
vim.api.nvim_command("highlight default " .. hlgroup .. " guifg=#ccffcc ctermfg=green")
-- FYI I like having a slightly different color vs predictions completions

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

local function ensure_new_lines_around(code, response_lines)
    -- * Ensure preserve blank line at start of selection (if present)
    local selected_lines = text_helpers.split_lines(code)
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
        table.insert(response_lines, selected_last_line)
    end

    return response_lines
end

function M.handle_messages_updated()
    -- ?? replace process_chunk?...
    --   get entire current refactor from the denormalizer?
    --   OR I can pass the latest chunk still...
    --   do smth in the normalizer for that or still have a sep pathway per delta (no chunkin though?)
end

local function clear_extmarks()
    vim.api.nvim_buf_clear_namespace(0, M.namespace_id, 0, -1)
end

---@diagnostic disable-next-line: unused-function   -- just long enough to test out new diff impl and keep this around just in case
local function show_green_preview_of_just_new_text(lines)
    clear_extmarks()

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
        M.selection.start_line_1indexed - 1, -- Zero-indexed
        M.selection.start_col_1indexed - 1, -- Zero-indexed
        {
            virt_text = first_line,
            virt_lines = virt_lines,
            virt_text_pos = "overlay",
            hl_mode = "combine"
        }
    )
end

---@param selection Selection
local function show_diff_ohhhhh_yeahhhhh(selection, lines)
    clear_extmarks()

    -- local first_line = { { table.remove(lines, 1), hlgroup } }
    -- -- Format remaining lines for virt_lines
    -- local virt_lines = {}
    -- for _, line in ipairs(lines) do
    --     table.insert(virt_lines, { { line, hlgroup } })
    -- end
    -- -- Set extmark at the beginning of the selection
    -- M.extmark_id = vim.api.nvim_buf_set_extmark(
    --     0, -- Current buffer
    --     M.namespace_id,
    --     M.selection.start_line_1indexed - 1, -- Zero-indexed
    --     M.selection.start_col_1indexed - 1, -- Zero-indexed
    --     {
    --         virt_text = first_line,
    --         virt_lines = virt_lines,
    --         virt_text_pos = "overlay",
    --         hl_mode = "combine"
    --     }
    -- )
end

function M.process_chunk(chunk)
    if not chunk then return end

    M.accumulated_chunks = M.accumulated_chunks .. chunk

    local lines = text_helpers.split_lines(M.accumulated_chunks)
    lines = M.strip_md_from_completion(lines)
    local pending_close = nil
    lines, pending_close = thinking.strip_thinking_tags(lines)
    if pending_close then
        lines = { thinking.dots:get_still_thinking_message() }
    end
    lines = ensure_new_lines_around(M.selection.original_text, lines)

    -- vim.schedule(function() show_green_preview_of_just_new_text(lines) end)
    vim.schedule(function() show_diff_ohhhhh_yeahhhhh(M.selection, lines) end)
end

function M.handle_request_completed()
end

function M.accept_rewrite()
    vim.schedule(function()
        local lines = text_helpers.split_lines(M.accumulated_chunks)
        lines = M.strip_md_from_completion(lines)
        lines = thinking.strip_thinking_tags(lines)
        lines = ensure_new_lines_around(M.selection.original_text, lines)

        local use_start_line_0indexed = M.selection.start_line_1indexed - 1
        local use_end_line_0indexed = M.selection.end_line_1indexed - 1
        local use_start_col_0indexed = M.selection.start_col_1indexed - 1
        local use_end_col_0indexed = M.selection.end_col_1indexed - 1

        log:info("nvim_buf_set_text: 0-indexed "
            .. "start(line=" .. use_start_line_0indexed
            .. ",col=" .. use_start_col_0indexed
            .. ") end(line=" .. use_end_line_0indexed
            .. ",col=" .. use_end_col_0indexed
            .. ")")

        -- TODO! study what to do to fix this, versus change how I select text in char/line/blockwise visual modes
        -- FYI notes about not replacing last character of selection
        --   select some text, i.e. viw => then <leader>rw => notice it doesn't show the char that was under the cursor as selected
        --     technically it wasn't selected, so possibly start selecting one more (cursor on char AFTER last char in selection)
        --     that's b/c the cursor is to the left of the char it is over...
        --     so, why not get used to selecting one more after...
        --     there are some settings in vim/nvim I should investigate for this
        --   working right now:
        --     linewise visual selections that end on an empty line work fine
        --     select thru end of current line (v$)
        --     AFAICT only when I select charwise do I have issues
        --       again that is when I wanna move the cursor to cover char AFTER end of selection I want
        --   DONT TRY A QUICK FIX.. try to change how you select first

        -- Dump selection in 0indexed for debugging too
        M.selection:log_info(true)

        -- Replace the selected text with the generated content
        vim.api.nvim_buf_set_text(
            0, -- Current buffer
            use_start_line_0indexed, -- Zero-indexed
            use_start_col_0indexed, -- Zero-indexed
            use_end_line_0indexed, -- Zero-indexed, end-inclusive line/row
            use_end_col_0indexed, -- Zero-indexed, end-exclusive column
            lines
        )

        clear_extmarks()

        -- Reset the module state
        M.accumulated_chunks = ""
        M.extmark_id = nil

        -- Log acceptance
        log:info("Rewrite accepted and inserted into buffer")
    end)
end

function M.cancel_rewrite()
    vim.schedule(function()
        clear_extmarks()

        -- PRN store this in a last_accumulated_chunks / canceled_accumulated_chunks?
        --  log similarly in accept?
        log:info("Canceling this rewrite: ", M.accumulated_chunks)

        -- Reset the module state
        M.accumulated_chunks = ""
        M.extmark_id = nil
    end)
end

function M.stream_from_ollama(user_prompt, code, file_name)
    M.abort_last_request()

    local system_prompt = "You are a neovim AI plugin that rewrites and/or creates new code. "
        .. "You strongly believe in the following: "
        .. "1. Explanations and markdown blocks are a waste of time. No ``` nor ` surrounding your work. "
        .. "2. Identation should be diligently preserved. "
        .. "3. Pointless comments are infuriating. "
        .. "4. Unrelated, existing code/comments must be carefully preserved (not removed, nor changed). "
        .. "5. If user instructions are ambiguous, it's paramount to ask for clarification. "
        .. "6. Adherence to the user's request is of utmost importance. "

    local user_message = user_prompt
    if code ~= nil and code ~= "" then
        user_message = user_message
            .. "\n Here is my code from " .. file_name
            .. ":\n\n" .. code
        log:info("user_message: '" .. user_message .. "'")
    else
        -- PRN detect if punctuation on end of user_message
        user_message = user_message
            .. "\n I am working on this file: " .. file_name
    end

    local qwen_chat_body = {
        messages = {
            { role = "system", content = system_prompt },
            { role = "user",   content = user_message },
        },
        --
        -- model = "qwen2.5-coder:7b-instruct-q8_0",
        model = "qwen3:8b", -- btw as of Qwen3, no tag == "-instruct", and for base you'll use "-base"
        --
        -- model = "deepseek-r1:8b-0528-qwen3-q8_0", -- /nothink doesn't work :(
        --
        -- model = "gemma3:12b-it-q8_0",
        max_tokens = 4096,
        temperature = 0.2,
        -- ?? do I need num_ctx (can't recall why I set it - check predicitons code)
        -- options = {
        --     num_ctx = 8192
        -- }
    }

    local qwen_legacy_body = {
        model = "qwen2.5-coder:7b-instruct-q8_0", -- btw -base- does terrible here :)
        prompt = system_prompt .. "\n" .. user_message,
        temperature = 0.2,
    }

    -- /v1/chat/completions
    -- local body = agentica.DeepCoder.build_chat_body(system_prompt, user_message)
    local body = qwen_chat_body

    -- /v1/completions
    -- local body = qwen_legacy_body

    -- vllm or ollama:
    -- local base_url = "http://build21:8000"
    local base_url = "http://ollama:11434"

    M.last_request = backend.curl_for(body, base_url, M)
end

local function ask_and_stream_from_ollama(opts)
    local selection = buffers.get_visual_selection()
    -- log:info("Selection: " .. selection:to_str())
    -- if selection:is_empty() then
    --     error("No visual selection found.")
    --     return
    -- end

    local user_prompt = opts.args
    local file_name = vim.fn.expand("%:t")

    -- Store selection details for later use
    M.selection = selection
    M.accumulated_chunks = ""
    selection:log_info()

    M.stream_from_ollama(user_prompt, selection.original_text, file_name)
end

function M.handle_request_failed(code)
    -- FYI test by pointing at the wrong server/port
    -- this is for AFTER the request completes and curl exits
    vim.schedule(function()
        -- for now just write into buffer is fine
        M.process_chunk("\nerror: request failed with code: " .. code)
    end)
end

function M.on_stderr_data(text)
    vim.schedule(function()
        M.process_chunk("\n" .. text)
    end)
end

function M.abort_last_request()
    if not M.last_request then
        -- PRN still clear extmarks just in case?
        return -- no request to abort
    end

    backend.terminate(M.last_request)

    clear_extmarks()
end

function M.setup()
    -- Create commands and keymaps for the rewrite functionality
    vim.api.nvim_create_user_command("AskRewrite", ask_and_stream_from_ollama, { range = true, nargs = 1 })
    vim.keymap.set({ 'n', 'v' }, '<Leader>rw', ':<C-u>AskRewrite ', { noremap = true })

    -- Add a command to abort the stream if needed
    vim.api.nvim_create_user_command("AskRewriteAbort", M.abort_last_request, {})
    vim.api.nvim_set_keymap('n', '<Leader>ra', ':AskRewriteAbort<CR>', { noremap = true })

    -- Add commands and keymaps for accepting or cancelling the rewrite
    vim.api.nvim_create_user_command("AskRewriteAccept", M.accept_rewrite, {})
    vim.api.nvim_set_keymap('n', '<Leader>ry', ':AskRewriteAccept<CR>', { noremap = true })

    vim.api.nvim_create_user_command("AskRewriteCancel", M.cancel_rewrite, {})
    vim.api.nvim_set_keymap('n', '<Leader>rc', ':AskRewriteCancel<CR>', { noremap = true })

    -- dump helpers while building this tooling - [a]sk [d]ump last [s]election
    vim.api.nvim_create_user_command("AskDumpLastSelection", buffers.dump_last_seletion, {})
    vim.api.nvim_set_keymap('n', '<Leader>ads', ':AskDumpLastSelection<CR>', { noremap = true })
    vim.api.nvim_set_keymap('v', '<Leader>ads', ':<C-u>AskDumpLastSelection<CR>', { noremap = true })
    -- FYI see notes in M.get_visual_selection about you don't want a lua func handler that calls dump
    -- also prints don't popup if they originated in a lua handler, whereas they do with a vim command
    --   thus w/ a cmd I get to see the vim.inspect(selection) with a pprint json like view of fields

    require("ask-openai.prediction.context.init").setup()
end

return M
