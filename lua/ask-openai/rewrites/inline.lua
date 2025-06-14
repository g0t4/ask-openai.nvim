local buffers = require("ask-openai.helpers.buffers")
local backend = require("ask-openai.backends.oai_chat")
-- local backend = require("ask-openai.backends.oai_completions")
local log = require("ask-openai.prediction.logger").predictions()
local agentica = require("ask-openai.backends.models.agentica")
local text_helpers = require("ask-openai.helpers.text")
local thinking = require("ask-openai.rewrites.thinking")
local Selection = require("ask-openai.helpers.selection")
local Displayer = require("ask-openai.rewrites.displayer")

local M = {}

-- Initialize selection position variables at module level
---@type Selection|nil
M.selection = nil
M.accumulated_chunks = ""

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

function M.process_chunk(chunk)
    if not chunk then return end

    M.accumulated_chunks = M.accumulated_chunks .. chunk

    local lines = text_helpers.split_lines(M.accumulated_chunks)
    lines = M.strip_md_from_completion(lines)
    local thinking_status = nil
    lines, thinking_status = thinking.strip_thinking_tags(lines)
    if thinking_status == thinking.ThinkingStatus.Thinking then
        lines = { thinking.dots:get_still_thinking_message() }
        -- while thinking, we show the green text w/ ....
        vim.schedule(function() M.displayer:show_green_preview_text(M.selection, lines) end)
        return
    end
    -- TODO! detect first chunk AFTER thinking section so we can clear the Thinking... message and not need to clear before every token
    -- FYI it looks fine to not add lines with the thinking message... just shows up right where cursor was at
    lines = ensure_new_lines_around(M.selection.original_text, lines)

    -- FYI can switch back to green here is fine! and skip diff if its not ready
    -- vim.schedule(function() M.displayer:show_green_preview_text(M.selection, lines) end)
    vim.schedule(function()
        M.displayer:on_response(M.selection, lines)
    end)
end

function M.handle_request_completed()
end

function M.accept_rewrite()
    M.stop_streaming = true -- go ahead and stop with whatever has been generated so far
    M.displayer = nil

    vim.schedule(function()
        local lines = text_helpers.split_lines(M.accumulated_chunks)
        lines = M.strip_md_from_completion(lines)
        lines = thinking.strip_thinking_tags(lines)
        lines = ensure_new_lines_around(M.selection.original_text, lines)

        -- FYI this may not be a problem with the linewise only mode that I setup for now with the streaming diff
        -- notes about not replacing last character of selection
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

        -- Insert (replace) the text right on the empty line added by the Displayer (it already removed the original lines)
        vim.api.nvim_buf_set_text(
            0, -- Current buffer
            M.selection:start_line_0indexed(), -- Zero-indexed
            -- set start col to zero always, b/c right now only support full line
            0, -- Zero-indexed
            M.selection:start_line_0indexed(), -- Zero-indexed
            -- set end line to zero always, b/c right now only support full line
            0, -- Zero-indexed, end-exclusive column
            lines
        )

        M.accumulated_chunks = ""
    end)
end

function M.abort_last_request()
    M.stop_streaming = true -- HACK to stop streaming simulations too

    if not M.last_request then
        return
    end

    backend.terminate(M.last_request)

    if M.displayer ~= nil then
        M.displayer:clear_extmarks()
    end
end

function M.cleanup_after_cancel()
    M.abort_last_request()
    M.displayer = nil

    -- PRN store this in a last_accumulated_chunks / canceled_accumulated_chunks?
    log:info("Canceling this rewrite: ", M.accumulated_chunks)

    M.accumulated_chunks = ""
end

function M.stream_from_ollama(user_prompt, code, file_name)
    M.abort_last_request()

    local system_prompt = "You are a neovim AI plugin. Your name is Qwenny. "
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
            .. ":\n" .. code
        log:info("user_message: '" .. user_message .. "'")
    else
        -- PRN detect if punctuation on end of user_message
        user_message = user_message
            .. "\n I am working on this file: " .. file_name
    end

    -- TODO add in context items? toggle for this?

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
        max_tokens = 8192, -- TODO set high if using /think only?
        temperature = 0.2,
        -- ?? do I need num_ctx (can't recall why I set it - check predicitons code)
        -- options = {
        --     num_ctx = 8192
        -- }
    }

    -- local qwen_legacy_body = {
    --     model = "qwen2.5-coder:7b-instruct-q8_0", -- btw -base- does terrible here :)
    --     prompt = system_prompt .. "\n" .. user_message,
    --     temperature = 0.2,
    -- }

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

M.stop_streaming = false
local function simulate_rewrite_stream_chunks(opts)
    -- use this for timing and to test streaming diff!

    M.abort_last_request()
    vim.cmd("normal! 0V6jV") -- down 5 lines from current position, 2nd v ends selection ('< and '> marks now have start/end positions)
    vim.cmd("normal! 5k") -- put cursor back before next steps (since I used 5j to move down for end of selection range
    M.selection = Selection.get_visual_selection_for_current_window()
    M.accumulated_chunks = ""
    M.stop_streaming = false
    M.displayer = Displayer:new(M.accept_rewrite, M.cleanup_after_cancel)
    M.displayer:set_keymaps()

    local optional_thinking_text = [[<think>
foo the bar lorem ipsum toodle doodle banana bie foo the bar bar the foo and foo the bar and bbbbbb the foo the bar bar the
foobar and foo the bar bar foo the bar lorem ipsum toodle doodle banana bie foo the bar bar the foo and foo the bar and bbbbbb
the foo the bar bar the foobar and foo the bar bar foo the bar lorem ipsum toodle doodle banana bie foo the bar bar the foo
and foo the bar and bbbbbb the foo the bar bar the foobar and foo the bar bar
</think> ]]
    local rewritten_text = optional_thinking_text .. M.selection.original_text .. "\nSTREAMING w/ THINKING CONTENT"
    -- local rewritten_text = M.selection.original_text .. "\nSTREAMING NEW CONTENT\nthis is fun"

    -- FYI can split on new line to simulate streaming lines instead of words
    local all_words = vim.split(rewritten_text, " ")

    local fast_ms = 20
    local slow_ms = 50

    local function stream_words(remaining_words)
        if not remaining_words
            or M.stop_streaming
        then
            -- TODO done signal? not sure I have one right now
            return
        end
        -- take out first word
        local cur_word = remaining_words[1]
        table.remove(remaining_words, 1) -- insert current word in middle of line
        if #remaining_words > 0 then
            -- put back the space
            cur_word = cur_word .. " "
        end
        M.process_chunk(cur_word)
        -- delay and do next
        -- FYI can adjust interval to visually slow down and see what is happening with each chunk, s/b especially helpful with streaming diff
        vim.defer_fn(function() stream_words(remaining_words) end, fast_ms)
    end
    stream_words(all_words)
end

local function simulate_rewrite_instant_one_chunk(opts)
    M.abort_last_request()
    vim.cmd("normal! 0V6jV") -- down 5 lines from current position, 2nd v ends selection ('< and '> marks now have start/end positions)
    vim.cmd("normal! 5k") -- put cursor back before next steps (since I used 5j to move down for end of selection range
    M.selection = Selection.get_visual_selection_for_current_window()
    M.accumulated_chunks = ""
    M.displayer = Displayer:new(M.accept_rewrite, M.cleanup_after_cancel)
    M.displayer:set_keymaps()

    local full_rewrite = M.selection.original_text .. "\nINSTANT NEW LINE"
    M.process_chunk(full_rewrite)
    -- FYI could call display method here and bypass M.process_chunk (mostly... need to set M.accumulated_chunks too)
end

local function ask_and_stream_from_ollama(opts)
    local selection = Selection.get_visual_selection_for_current_window()
    -- if selection:is_empty() then
    --     error("No visual selection found.")
    --     return
    -- end

    local user_prompt = opts.args
    local file_name = vim.fn.expand("%:t")

    -- Store selection details for later use
    M.selection = selection
    M.accumulated_chunks = ""
    M.displayer = Displayer:new(M.accept_rewrite, M.cleanup_after_cancel)
    M.displayer:set_keymaps()

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

local function retry()
    if M.displayer then
        M.displayer:reject()
    end

    local function run_last_command_that_started_with(filter)
        -- PRN if I like this, move it to devtools
        -- start typing the command, just like a user would:
        vim.fn.feedkeys(":" .. filter, "n")
        -- then hit Up to take last from the history
        -- and Enter to execute it
        vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Up><CR>", true, false, true), "n")
    end

    -- schedule so it runs after any cancel logic that is scheduled
    vim.schedule(function()
        -- for when the last command failed, try it again, i.e. you forgot to start ollama
        -- assume can just go back in history and grab it and run it
        -- by the way, AFAICT there's no way to search command history
        run_last_command_that_started_with('AskRewrite')
    end)
end

function M.setup()
    -- Create commands and keymaps for the rewrite functionality
    vim.api.nvim_create_user_command("AskRewrite", ask_and_stream_from_ollama, { range = true, nargs = 1 })
    vim.keymap.set({ 'n', 'v' }, '<Leader>rw', ':<C-u>AskRewrite ', { noremap = true })

    vim.keymap.set({ 'n', 'v' }, '<Leader>ry', retry, { noremap = true })

    -- * simulations
    vim.api.nvim_create_user_command("AskRewriteSimulateInstant", simulate_rewrite_instant_one_chunk, {})
    vim.keymap.set({ 'n' }, '<Leader>rt', ':<C-u>AskRewriteSimulateInstant<CR>', { noremap = true })
    --
    vim.api.nvim_create_user_command("AskRewriteSimulateStream", simulate_rewrite_stream_chunks, {})
    vim.keymap.set({ 'n' }, '<Leader>rs', ':<C-u>AskRewriteSimulateStream<CR>', { noremap = true })

    -- dump helpers while building this tooling - [a]sk [d]ump last [s]election
    vim.api.nvim_create_user_command("AskDumpLastSelection", buffers.dump_last_seletion, {})
    vim.api.nvim_set_keymap('n', '<Leader>ads', ':AskDumpLastSelection<CR>', { noremap = true })
    vim.api.nvim_set_keymap('v', '<Leader>ads', ':<C-u>AskDumpLastSelection<CR>', { noremap = true })
    -- FYI see notes in M.get_visual_selection about you don't want a lua func handler that calls dump
    -- also prints don't popup if they originated in a lua handler, whereas they do with a vim command
    --   thus w/ a cmd I get to see the vim.inspect(selection) with a pprint json like view of fields

    require("ask-openai.prediction.context").setup()
end

return M
