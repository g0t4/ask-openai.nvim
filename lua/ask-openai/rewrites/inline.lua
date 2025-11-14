local buffers = require("ask-openai.helpers.buffers")
---@type CurlMiddle
local backend = require("ask-openai.backends.oai_chat")
-- local backend = require("ask-openai.backends.oai_completions")
local log = require("ask-openai.logs.logger").predictions()
local agentica = require("ask-openai.backends.models.agentica")
local text_helpers = require("ask-openai.helpers.text")
local thinking = require("ask-openai.rewrites.thinking")
local Selection = require("ask-openai.helpers.selection")
local Displayer = require("ask-openai.rewrites.displayer")
local CurrentContext = require("ask-openai.prediction.context")
local ChatMessage = require("ask-openai.questions.chat_message")
local files = require("ask-openai.helpers.files")
local api = require("ask-openai.api")
local rag_client = require("ask-openai.rag.client")
local LastRequest = require("ask-openai.backends.last_request")
local human = require("devtools.humanize")
local tool_router = require("ask-openai.tools.router")
local model_params = require("ask-openai.questions.models.params")
local MessageBuilder = require("ask-openai.rewrites.message_builder")

---@class AskInlineRewriteFrontend : StreamingFrontend
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
    -- ?? replace on_generated_text?...
    --   get entire current refactor from the denormalizer?
    --   OR I can pass the latest chunk still...
    --   do smth in the normalizer for that or still have a sep pathway per delta (no chunkin though?)
end

function M.on_generated_text(chunk)
    if not chunk then return end
    if not M.displayer then return end -- else after cancel, if get another SSE, boom

    M.accumulated_chunks = M.accumulated_chunks .. chunk

    local lines = text_helpers.split_lines(M.accumulated_chunks)
    lines = M.strip_md_from_completion(lines)
    local thinking_status = nil
    lines, thinking_status = thinking.strip_thinking_tags(lines)
    if thinking_status == thinking.ThinkingStatus.Thinking then
        lines = { thinking.dots:get_still_thinking_message(M.last_request.start_time) }
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

function M.on_sse_llama_server_timings(sse)
    -- FYI coupled to llama-server timings
    if sse == nil or sse.timings == nil then
        return
    end

    vim.schedule(function()
        -- PRN move into displayer where this belongs w/ diff preview
        local current_cursor_row_1based, _ = unpack(vim.api.nvim_win_get_cursor(0))
        local current_cursor_row_0based = current_cursor_row_1based - 2
        if current_cursor_row_0based < 0 then current_cursor_row_0based = 0 end

        local virt_text = {
            {
                string.format(
                    "%sout@%stps",
                    human.comma_delimit(sse.timings.predicted_n),
                    human.format_num(sse.timings.predicted_per_second)
                ),
                "AskStatsPredicted",
            },
            {
                string.format(
                    " %sin@%stps",
                    human.comma_delimit(sse.timings.prompt_n),
                    human.format_num(sse.timings.prompt_per_second)
                ),
                "AskStatsPrompt",
            },
            {
                string.format(
                    " %scached",
                    human.comma_delimit(sse.timings.cache_n or 0)
                ),
                "AskStatsCached",
            },
        }

        vim.api.nvim_buf_set_extmark(0, M.displayer.marks.namespace_id, current_cursor_row_0based, 0, {
            virt_text = virt_text,
            virt_text_pos = "eol",
            hl_mode = "combine",
        })
    end)
end

function M.curl_request_exited_successful_on_zero_rc()
end

function M.accept_rewrite()
    M.stop_streaming = true -- go ahead and stop with whatever has been generated so far
    M.displayer = nil

    vim.schedule(function()
        local lines = text_helpers.split_lines(M.accumulated_chunks)
        lines = M.strip_md_from_completion(lines)
        lines = thinking.strip_thinking_tags(lines)
        lines = ensure_new_lines_around(M.selection.original_text, lines)

        log:info("Accepted rewrite (accumulated_chunks): ", M.accumulated_chunks)
        -- log "sanitized" version of what is inserted:
        local lines_joined = table.concat(lines, "\n")
        log:info("Accepted rewrite (lines): ", lines_joined)

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
    log:info("Cancel rewrite (accumulated_chunks): ", M.accumulated_chunks)

    M.accumulated_chunks = ""
end

function M.stream_from_ollama(user_prompt, code, file_name)
    M.abort_last_request()

    -- local enable_rag = false
    local enable_rag = api.is_rag_enabled()

    local markdown_exclusion = "\n- DO NOT wrap answers in markdown code blocks, which"
        .. " means no triple backticks like ``` nor single backtick like ` ."
    if file_name:match(".*.md$") then
        markdown_exclusion = ""
    end
    local system_prompt = "You are an expert coder. Ground rules:"
        .. "\n- Follow the user's instructions. "
        .. markdown_exclusion
        .. "\n- Do not explain answers, just give me code. "
        .. "\n- Never add comments to the end of a line. "
        .. "\n- Never add comments."
        .. "\n- Preserve indentation. "
        .. "\n- If rewriting code, preserve unrelated code. "
        .. "\n- Prefer readable code over of comments. "

    local always_include = {
        yanks = true,
        project = true,
    }
    local context = CurrentContext:items(user_prompt, always_include)
    -- log:info("user_prompt: '" .. user_prompt .. "'")
    -- log:info("context: '" .. vim.inspect(context) .. "'")
    -- log:info("includes: '" .. vim.inspect(context.includes) .. "'")

    -- make sure to remove slash commands like /yanks (hence cleaned_prompt)
    local user_prompt = context.cleaned_prompt
    local code_context = ""
    if code ~= nil and code ~= "" then
        -- FYI I added the note about "carefully preserved indentation" to attempt to improve chances the indented code is correct
        --   TODO ? add manual test to verify % accuracy preserving indentation
        --   i.e. see commit 69723fe4 for spelling correction request results that had indentation issues before prompt change
        --   ALTERNATIVELY, if I could show more of the surrounding code, that would likely help too/instead
        --     think the style that zed used for Edit Predictions (finetune on qwen25dcoder7b)
        --   FYI - huge, uninteneded effect, mentioning carefully indented resulted in the model not generating markdown wrapers and explanations! (gptoss120b)
        --     :AskRewrite please review and just fix spelling only
        --     - previously I'd get markdown and explanations! now I only get the fixed code!
        code_context = "Here is code I selected (with carefully preserved indentation) from " .. file_name
            .. ":\n" .. code
    else
        code_context = "I am working on this file: " .. file_name
    end
    user_message_with_code = user_prompt .. "\n" .. code_context
    log:info("user_message_with_code: '" .. user_message_with_code .. "'")

    ---@param rag_matches LSPRankedMatch[]
    local function send_rewrite(rag_matches)
        local messages = {
            { role = "system", content = system_prompt }
        }

        if context.includes.current_file then
            -- get this again, just in case somehow the current buffer is not the filename above
            local file_name = files.get_current_file_relative_path()
            local entire_file = buffers.get_text_in_current_buffer()

            local user_message = MessageBuilder:new()
                :plain_text("FYI, here is my current buffer in Neovim. Use this as context for my request.")
                :md_code_block(file_name, entire_file)
                :build()

            table.insert(messages, ChatMessage:user(user_message))
        end
        if context.includes.open_files then
            -- TODO! /files => open_files
            -- FYI buffers.get_text_in_all_buffers()
        end
        if context.includes.yanks and context.yanks then
            table.insert(messages, ChatMessage:user(context.yanks.content))
        end
        if context.includes.commits and context.commits then
            for _, commit in pairs(context.commits) do
                table.insert(messages, ChatMessage:user(commit.content))
            end
        end
        if context.includes.project and context.project then
            vim.iter(context.project)
                :each(function(value)
                    table.insert(messages, ChatMessage:user(value.content))
                end)
        end
        if enable_rag and rag_matches ~= nil and #rag_matches > 0 then
            rag_message_parts = {}
            if #rag_matches == 1 then
                heading = "# RAG query match: \n"
            elseif #rag_matches > 1 then
                heading = "# RAG query matches: " .. #rag_matches .. "\n"
            end
            table.insert(rag_message_parts, heading)
            -- TODO! dedupe matches that overlap/touch dedupe.merge_contiguous_rag_chunks()
            vim.iter(rag_matches)
                :each(function(chunk)
                    ---@cast chunk LSPRankedMatch
                    local file = chunk.file .. ":" .. chunk.start_line_base0 .. "-" .. chunk.end_line_base0
                    local code_chunk = chunk.text
                    table.insert(rag_message_parts,
                        "## " .. file .. "\n"
                        .. code_chunk .. "\n"
                    )
                end)
            table.insert(messages, ChatMessage:user(table.concat(rag_message_parts, "\n")))
        end

        table.insert(messages, ChatMessage:user(user_message_with_code))

        local qwen25_chat_body = {
            messages = messages,
            -- * current models only
            -- model = "qwen3:8b", -- btw as of Qwen3, no tag == "-instruct", and for base you'll use "-base" # VERY HAPPY WITH THIS MODEL FOR CODING TOO!
            -- model = "qwen3-coder:30b-a3b-q8_0", # q4_K_M
            temperature = 0.2,

            -- avoid num_ctx (s/b set server side), use max_tokens to cap request:
            max_tokens = 8192, -- PRN set high if using /think only?
        }

        local body = model_params.new_gptoss_chat_body_llama_server({
            -- local body = model_params.new_qwen3coder_llama_server_chat_body({
            messages = messages,
            model = "", -- irrelevant for llama-server
            -- tools = tool_router.openai_tools(),
        })

        local base_url = "http://ollama:8013"

        M.last_request = backend.curl_for(body, base_url, M)
    end

    if enable_rag and rag_client.is_rag_supported_in_current_file() then
        local this_request_ids, cancel -- declare in advance for closure

        ---@param rag_matches LSPRankedMatch[]
        ---@param rag_failed boolean?
        function on_rag_response(rag_matches, rag_failed)
            -- * make sure prior (canceled) rag request doesn't still respond
            if M.rag_request_ids ~= this_request_ids then
                log:trace("possibly stale rag results, skipping: "
                    .. vim.inspect({ global_rag_request_ids = M.rag_request_ids, this_request_ids = this_request_ids }))
                return
            end

            if M.rag_cancel == nil then
                log:error("rag appears to have been canceled, skipping on_rag_response rag_matches results...")
                return
            end

            send_rewrite(rag_matches)
        end

        this_request_ids, cancel = rag_client.context_query_rewrites(user_prompt, code_context, send_rewrite)
        M.rag_cancel = cancel
        M.rag_request_ids = this_request_ids
    else
        M.rag_cancel = nil
        M.rag_request_ids = nil
        -- PRN add a promise fwk in here
        send_rewrite({})
    end
end

M.stop_streaming = false
local function simulate_rewrite_stream_chunks(opts)
    -- use this for timing and to test streaming diff!

    M.abort_last_request()
    M.last_request = LastRequest:new() -- PRN pass fake body?
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

    local harmony_gptoss_example =
    [[<|channel|>analysis<|message|>User wrote "test". Likely just a test message. They might want ChatGPT to respond? We should respond politely. Maybe just say "Hello! How can I help?"<|end|>Hello! 👋 How can I assist you today?]]
    local rewritten_text = harmony_gptoss_example .. M.selection.original_text .. "\nSIMULATED HARMONY EXAMPLE"

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
        local simulated_sse = {}
        if #remaining_words > 0 then
            -- put back the space
            cur_word = cur_word .. " "
        else
            simulated_sse = {
                timings = {
                    cache_n = 1000,
                    predicted_per_second = 120,
                    predicted_n = 100,
                    prompt_per_second = 200,
                    prompt_n = 400,
                }
            }
        end
        M.on_generated_text(cur_word, simulated_sse)

        -- delay and do next
        -- FYI can adjust interval to visually slow down and see what is happening with each chunk, s/b especially helpful with streaming diff
        vim.defer_fn(function() stream_words(remaining_words) end, fast_ms)
    end
    stream_words(all_words)
end

local function simulate_rewrite_instant_one_chunk(opts)
    M.abort_last_request()
    M.last_request = LastRequest:new() -- PRN pass fake body?
    vim.cmd("normal! 0V6jV") -- down 5 lines from current position, 2nd v ends selection ('< and '> marks now have start/end positions)
    vim.cmd("normal! 5k") -- put cursor back before next steps (since I used 5j to move down for end of selection range
    M.selection = Selection.get_visual_selection_for_current_window()
    M.accumulated_chunks = ""
    M.displayer = Displayer:new(M.accept_rewrite, M.cleanup_after_cancel)
    M.displayer:set_keymaps()

    local full_rewrite = M.selection.original_text .. "\nINSTANT NEW LINE"
    local simulated_sse = {
        timings = {
            cache_n = 1000,
            predicted_per_second = 120,
            predicted_n = 100,
            prompt_per_second = 200,
            prompt_n = 400,
        }
    }
    M.on_generated_text(full_rewrite, simulated_sse)
end

local function ask_and_stream_from_ollama(opts)
    local selection = Selection.get_visual_selection_for_current_window()
    -- if selection:is_empty() then
    --     error("No visual selection found.")
    --     return
    -- end

    local user_prompt = opts.args
    local relative_file_path = files.get_current_file_relative_path()
    -- Store selection details for later use
    M.selection = selection
    M.accumulated_chunks = ""
    M.displayer = Displayer:new(M.accept_rewrite, M.cleanup_after_cancel)
    M.displayer:set_keymaps()

    M.stream_from_ollama(user_prompt, selection.original_text, relative_file_path)
end

function M.on_sse_llama_server_error_explanation(sse_parsed)
    if sse_parsed.error then
        if M.displayer then
            vim.schedule(function()
                M.displayer:explain_error(M.selection, vim.inspect(sse_parsed.error))
            end)
        end
    end
end

function M.on_stderr_data(text)
    vim.schedule(function()
        M.on_generated_text("\n" .. text)
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
