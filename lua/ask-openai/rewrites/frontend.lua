local buffers = require("ask-openai.helpers.buffers")
local curl = require("ask-openai.backends.curl")
local log = require("ask-openai.logs.logger").predictions()
local agentica = require("ask-openai.backends.models.agentica")
local text_helpers = require("ask-openai.helpers.text")
local thinking = require("ask-openai.rewrites.thinking")
local Selection = require("ask-openai.helpers.selection")
local Displayer = require("ask-openai.rewrites.displayer")
local CurrentContext = require("ask-openai.predictions.context")
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")
local files = require("ask-openai.helpers.files")
local api = require("ask-openai.api")
local rag_client = require("ask-openai.rag.client")
local CurlRequest = require("ask-openai.backends.curl_request")
local human = require("devtools.humanize")
local tool_router = require("ask-openai.tools.router")
local model_params = require("ask-openai.questions.models.params")
local MessageBuilder = require("ask-openai.rewrites.message_builder")
local HLGroups = require("ask-openai.hlgroups")
local harmony = require("ask-openai.backends.models.gptoss.tokenizer").harmony
local prompts = require("ask-openai.frontends.prompts")

---@class RewriteFrontend : StreamingFrontend
local RewriteFrontend = {}

-- Initialize selection position variables at module level
---@type Selection|nil
RewriteFrontend.selection = nil
RewriteFrontend.accumulated_chunks = ""

function RewriteFrontend.strip_md_from_completion(lines)
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

---@alias ExtractGeneratedTextFromChoiceFunction fun(first_choice: table): string

---@param endpoint CompletionsEndpoints
---@return ExtractGeneratedTextFromChoiceFunction
local function get_extract_generated_text_func(endpoint)
    -- * /completions  CompletionsEndpoints.llamacpp_completions
    --   3rd ExtractGeneratedTextFromChoiceFunction for non-openai /completions endpoint on llama-server
    --     => no sse.choice so I'd have to change how M.on_one_data_value works to not assume sse.choices
    --     whereas with non-openai /completions it would just use top-level to get text (.content)
    if endpoint == CompletionsEndpoints.oai_v1_completions then
        ---@type ExtractGeneratedTextFromChoiceFunction
        return function(choice)
            --- * /v1/completions
            if choice == nil or choice.text == nil then
                -- just skip if no (first) choice or no text on it (i.e. last SSE is often timing only)
                return ""
            end
            return choice.text
        end
    end

    if endpoint == CompletionsEndpoints.oai_v1_chat_completions then
        ---@type ExtractGeneratedTextFromChoiceFunction
        return function(choice)
            --- * /v1/chat/completions
            -- NOW I have access to request (url, body.model, etc) to be able to dynamically swap in the right SSE parser!
            --   I could even add another function that would handle aggregating and transforming the raw response (i.e. for harmony) into aggregate views (i.e. of thinking and final responses), also trigger events that way
            if choice == nil
                or choice.delta == nil
                or choice.delta.content == nil
                or choice.delta.content == vim.NIL
            then
                return ""
            end
            return choice.delta.content
        end
    end

    if endpoint == CompletionsEndpoints.llamacpp_completions then
        error("TODO /completions endpoint's ExtractGeneratedTextFromChoiceFunction")
    end

    -- TODO CompletionsEndpoints.llamacpp_completions /completions for 3rd ExtractGeneratedTextFromChoiceFunction
    error("Not yet implemented: " .. endpoint)
end

---@type OnParsedSSE
function RewriteFrontend.on_parsed_data_sse(sse_parsed)
    if sse_parsed.choices == nil or sse_parsed.choices[1] == nil then
        return
    end

    local first_choice = sse_parsed.choices[1]
    -- FYI get_extract_generated_text_func shows support for both OpenAI endpoints: /v1/chat/completions and /v1/completions !
    --   TODO and you can add others, just provide a relevant extractor function!
    local extract_generated_text = get_extract_generated_text_func(RewriteFrontend.last_request.endpoint)
    local content_chunk = extract_generated_text(first_choice)
    if not content_chunk then return end

    if not RewriteFrontend.displayer then return end -- else after cancel, if get another SSE, boom

    RewriteFrontend.accumulated_chunks = RewriteFrontend.accumulated_chunks .. content_chunk

    local lines = text_helpers.split_lines(RewriteFrontend.accumulated_chunks)
    lines = RewriteFrontend.strip_md_from_completion(lines)
    local thinking_status = nil
    -- TODO vestigial (stripping think tags), instead use reasoning_content off of SSE now (w/ --jinja on server side)
    lines, thinking_status = thinking.strip_thinking_tags(lines)
    if thinking_status == thinking.ThinkingStatus.Thinking then
        lines = { thinking.dots:get_still_thinking_message(RewriteFrontend.last_request.start_time) }
        -- while thinking, we show the green text w/ ....
        vim.schedule(function() RewriteFrontend.displayer:show_green_preview_text(RewriteFrontend.selection, lines) end)
        return
    end

    lines = ensure_new_lines_around(RewriteFrontend.selection.original_text, lines)

    vim.schedule(function()
        -- FYI the diff tool can handle massive changes to many, many lines... not sure what is slowing things down at times w/ llama-server and some bigger requests?
        --   almost wonder if it is the verbose logging b/c that actually ends up failing (the logs) midway and I never see final messages, (--verbose and --verbose-prompt)
        RewriteFrontend.displayer:on_response(RewriteFrontend.selection, lines)
    end)
end

---@type OnParsedSSE
function RewriteFrontend.on_sse_llama_server_timings(sse)
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
                HLGroups.STATS_PREDICTED
            },
            {
                string.format(
                    " %sin@%stps",
                    human.comma_delimit(sse.timings.prompt_n),
                    human.format_num(sse.timings.prompt_per_second)
                ),
                HLGroups.STATS_PROMPT
            },
        }

        local cache_n = sse.timings.cache_n
        if type(cache_n) == "number" and cache_n > 0 then
            table.insert(virt_text, {
                string.format(
                    " %scached",
                    human.comma_delimit(cache_n)
                ),
                HLGroups.STATS_CACHE
            })
        end

        vim.api.nvim_buf_set_extmark(0, RewriteFrontend.displayer.marks.namespace_id, current_cursor_row_0based, 0, {
            virt_text = virt_text,
            virt_text_pos = "eol",
            hl_mode = "combine",
        })
    end)
end

---@type OnCurlExitedSuccessfully
function RewriteFrontend.on_curl_exited_successfully()
end

function RewriteFrontend.accept_rewrite()
    RewriteFrontend.stop_streaming = true -- go ahead and stop with whatever has been generated so far
    RewriteFrontend.displayer = nil

    vim.schedule(function()
        local lines = text_helpers.split_lines(RewriteFrontend.accumulated_chunks)
        lines = RewriteFrontend.strip_md_from_completion(lines)
        lines = thinking.strip_thinking_tags(lines)
        lines = ensure_new_lines_around(RewriteFrontend.selection.original_text, lines)

        -- log:info("Accepted rewrite (accumulated_chunks): ", M.accumulated_chunks)
        -- log:info("Accepted rewrite (inserted lines, sanitized): ", table.concat(lines, "\n"))

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
            RewriteFrontend.selection:start_line_0indexed(), -- Zero-indexed
            -- set start col to zero always, b/c right now only support full line
            0, -- Zero-indexed
            RewriteFrontend.selection:start_line_0indexed(), -- Zero-indexed
            -- set end line to zero always, b/c right now only support full line
            0, -- Zero-indexed, end-exclusive column
            lines
        )

        RewriteFrontend.accumulated_chunks = ""
    end)
end

function RewriteFrontend.abort_last_request()
    RewriteFrontend.stop_streaming = true -- HACK to stop streaming simulations too

    if not RewriteFrontend.last_request then
        return
    end

    CurlRequest.terminate(RewriteFrontend.last_request)

    if RewriteFrontend.displayer ~= nil then
        RewriteFrontend.displayer:clear_extmarks()
    end
end

function RewriteFrontend.cleanup_after_cancel()
    RewriteFrontend.abort_last_request()
    RewriteFrontend.displayer = nil

    -- PRN store this in a last_accumulated_chunks / canceled_accumulated_chunks?
    -- log:info("Cancel rewrite (accumulated_chunks): ", M.accumulated_chunks)

    RewriteFrontend.accumulated_chunks = ""
end

---@param opts {args:string}
local function ask_rewrite_command(opts)
    RewriteFrontend.abort_last_request()

    local selection = Selection.get_visual_selection_for_current_window()

    local user_prompt = opts.args
    local file_name = files.get_current_file_relative_path()

    -- Store selection details for later use
    RewriteFrontend.selection = selection
    RewriteFrontend.accumulated_chunks = ""
    RewriteFrontend.displayer = Displayer:new(RewriteFrontend.accept_rewrite, RewriteFrontend.cleanup_after_cancel)
    RewriteFrontend.displayer:set_keymaps()

    -- TODO revisit messaging around:
    -- TODO fix issues with indentation? not sure this is concrete!
    -- TODO gptoss prompt review:
    --   TODO review system (dev) message vs user message...
    --     ? incomplete code (not to generate surrounding code if I didn't select it to start!)
    --     markdown code block prohibition... should I flip this and assert it should be there?
    --        only one code block and it should be added always?
    --        this might help structure the response in a more intuitive way!
    --        I already strip it around full response
    --        I could add logic to strip multiple
    --   TODO be assertive
    --   TODO do not strive for concise instructions, explain it well
    --   TODO track gptoss specific instructions (dev msg, user msg, etc)?
    --   TODO review indentation instructions
    --      explain when there is a selection, that has indentation carefully preserved
    --      TODO document examples of problematic indentation (flag them) in my dataset repo
    --        TODO reproduce? cases where response preview looks correct for indentation, but then de-indents on accept?

    local markdown_exclusion = "\n- DO NOT wrap answers in markdown code blocks, which"
        .. " means no triple backticks like ``` nor single backtick like ` ."
    if file_name:match(".*.md$") then
        markdown_exclusion = ""
    end

    local system_prompt = "## Ground rules:"
        .. "\n- Follow the user's instructions. "
        .. markdown_exclusion
        .. "\n- Do not explain answers, just give me code. "
        .. "\n- If changing existing code, preserve unrelated code and comments. "
        .. "\n- Never add comments to the end of a line. "
        -- IIRC I had to add "Never add comments" to get gptoss to knock it off! PRN verify and add it back if it starts again
        .. "\n- Never add stupid comments."
        .. "\n- Be considerate with indentation. "
        .. "\n- Prefer readable code over of comments. "
        .. "\n- Prefer meaningful names for variables, functions, etc. Avoid ambiguous names."

    local always_include = {
        yanks = true,
        project = true,
    }
    local context = CurrentContext:items(user_prompt, always_include)

    -- make sure to remove slash commands like /yanks (hence cleaned_prompt)
    local user_prompt = context.cleaned_prompt
    local code_context = ""
    local code_caveat = ""
    local code = selection.original_text
    if code ~= nil and code ~= "" then
        -- Compute line range for the selection (1-indexed for user readability)
        local start_line = (selection._start_line_0indexed or 0) + 1
        local end_line = (selection._end_line_0indexed or 0) + 1
        local line_info = start_line == end_line and tostring(start_line) or (start_line .. "-" .. end_line)
        code_context = "Here is the code I selected:"
            .. "\n```" .. file_name .. ":" .. line_info
            .. "\n" .. code .. "\n```"
        code_caveat = "\n\nThis is not necessarily a complete selection of nearby code, this is just the part I want help with. Preserve indentation!"
        -- TODO add separate reasoning level for rewrites/questions vs predictions... that should help here and with tool calls too!
        -- * response indentation:
        -- - ALTERNATIVELY, if I could show more of the surrounding code, that would likely help too/instead
        -- - FYI mentioning "carefully preserved indentation" resulted in the model not generating markdown wrapers and explanations! (gptoss120b)
        --   - btw I strip out markdown blocks so really, I don't care anymore if those are present in the response!
        -- - FYI gptoss120b w/ medium reasoning + caveat is working well
        --   - cannot get low reasoning to work well
    else
        code_context = "I am working on this file: " .. file_name
    end
    user_message_with_code = user_prompt .. "\n\n" .. code_context .. code_caveat

    ---@param rag_matches LSPRankedMatch[]
    local function then_send_rewrite(rag_matches)
        local messages = {
            TxChatMessage:system(system_prompt)
        }

        if context.includes.current_file then
            local message = MessageBuilder:new()
                :plain_text("FYI, here is my current buffer in Neovim. Use this as context for my request.")
                :md_current_buffer()
                :to_user_message()

            table.insert(messages, message)
        end
        if context.includes.open_files then
            -- TODO! /files => open_files
            -- FYI buffers.get_text_in_all_buffers()
        end
        if context.includes.yanks and context.yanks then
            table.insert(messages, TxChatMessage:user_context(context.yanks.content))
        end
        if context.includes.commits and context.commits then
            for _, commit in pairs(context.commits) do
                table.insert(messages, TxChatMessage:user_context(commit.content))
            end
        end
        if context.includes.project and context.project then
            -- TODO does any of this belong in the system_message?
            vim.iter(context.project)
                :each(function(value)
                    table.insert(messages, TxChatMessage:user_context(value.content))
                end)
        end
        local rag_message = prompts.semantic_grep_user_message(rag_matches)
        if rag_message then
            table.insert(messages, rag_message)
        end

        table.insert(messages, TxChatMessage:user(user_message_with_code))

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

        RewriteFrontend.last_request = CurlRequest:new({
            body = body,
            base_url = "http://build21:8013",
            endpoint = CompletionsEndpoints.oai_v1_chat_completions,
            type = "rewrite",
        })
        curl.spawn(RewriteFrontend.last_request, RewriteFrontend)
    end

    if api.is_rag_enabled() and rag_client.is_rag_supported_in_current_file() then
        local this_request_ids, cancel -- declare in advance for closure

        ---@param rag_matches LSPRankedMatch[]
        function on_rag_response(rag_matches)
            -- PRN I think this could be shared with all frontends... if they pass themself for access to ID/cancel refs

            -- * make sure prior (canceled) rag request doesn't still respond
            if RewriteFrontend.rag_request_ids ~= this_request_ids then
                log:trace("possibly stale rag results, skipping: " .. vim.inspect({
                    global_rag_request_ids = RewriteFrontend.rag_request_ids,
                    this_request_ids = this_request_ids,
                }))
                return
            end

            if RewriteFrontend.rag_cancel == nil then
                log:error("rag appears canceled, skipping on_rag_response...")
                return
            end

            then_send_rewrite(rag_matches)
        end

        -- TODO should abort logic also clear rag_cancel/rag_request_ids?
        this_request_ids, cancel = rag_client.context_query_rewrites(user_prompt, code_context, context.includes.top_k, on_rag_response)
        RewriteFrontend.rag_cancel = cancel
        RewriteFrontend.rag_request_ids = this_request_ids
    else
        RewriteFrontend.rag_cancel = nil
        RewriteFrontend.rag_request_ids = nil
        -- PRN add a promise fwk in here
        then_send_rewrite({})
    end
end

RewriteFrontend.stop_streaming = false
local function simulate_streaming_rewrite_command(opts)
    -- use this for timing and to test streaming diff!

    RewriteFrontend.abort_last_request()
    RewriteFrontend.last_request = CurlRequest:new({ body = {}, base_url = "base", endpoint = CompletionsEndpoints.oai_v1_chat_completions, })
    vim.cmd("normal! 0V60jV") -- down 5 lines from current position, 2nd v ends selection ('< and '> marks now have start/end positions)
    vim.cmd("normal! 59k") -- put cursor back before next steps (since I used 5j to move down for end of selection range
    RewriteFrontend.selection = Selection.get_visual_selection_for_current_window()
    RewriteFrontend.accumulated_chunks = ""
    RewriteFrontend.stop_streaming = false
    RewriteFrontend.displayer = Displayer:new(RewriteFrontend.accept_rewrite, RewriteFrontend.cleanup_after_cancel)
    RewriteFrontend.displayer:set_keymaps()

    local optional_thinking_text = [[<think>
foo the bar lorem ipsum toodle doodle banana bie foo the bar bar the foo and foo the bar and bbbbbb the foo the bar bar the
foobar and foo the bar bar foo the bar lorem ipsum toodle doodle banana bie foo the bar bar the foo and foo the bar and bbbbbb
the foo the bar bar the foobar and foo the bar bar foo the bar lorem ipsum toodle doodle banana bie foo the bar bar the foo
and foo the bar and bbbbbb the foo the bar bar the foobar and foo the bar bar
</think> ]]
    -- local rewritten_text = optional_thinking_text .. RewriteFrontend.selection.original_text .. "\nSTREAMING w/ THINKING CONTENT"
    -- local rewritten_text = M.selection.original_text .. "\nSTREAMING NEW CONTENT\nthis is fun"

    -- local jumble = RewriteFrontend.selection.original_text:gsub("(%S+)%s+(%S+)", "%1 (%2)")
    local jumble = table.concat(vim.fn.reverse(vim.split(RewriteFrontend.selection.original_text, "\n")))

    local harmony_gptoss_example =
        harmony.CHANNEL .. "analysis" ..
        harmony.MESSAGE .. [[User wrote "test". Likely just a test message. They might want ChatGPT to respond? We should respond politely. Maybe just say "Hello! How can I help?"]] ..
        harmony.END .. [[Hello! 👋 How can I assist you today?]]

    local rewritten_text = harmony_gptoss_example .. jumble .. "\nSIMULATED HARMONY EXAMPLE"

    -- FYI can split on new line to simulate streaming lines instead of words
    local all_words = vim.split(rewritten_text, " ")

    local fast_ms = 20
    local slow_ms = 50

    local function stream_words(remaining_words)
        if not remaining_words
            or RewriteFrontend.stop_streaming
        then
            return
        end

        local cur_word = remaining_words[1]
        table.remove(remaining_words, 1)
        if #remaining_words > 0 then
            -- put back the space
            cur_word = cur_word .. " "
        end

        local simulated_sse = { choices = { { delta = { content = cur_word } } } }

        if #remaining_words == 0 then
            -- fake stats on last SSE
            simulated_sse.timings = {
                cache_n = 1000,
                predicted_per_second = 120,
                predicted_n = 100,
                prompt_per_second = 200,
                prompt_n = 400,
            }
        end
        RewriteFrontend.on_parsed_data_sse(simulated_sse)

        -- delay and do next
        -- FYI can adjust interval to visually slow down and see what is happening with each chunk, s/b especially helpful with streaming diff
        vim.defer_fn(function() stream_words(remaining_words) end, fast_ms)
    end
    stream_words(all_words)
end

local function simulate_instant_rewrite_command(opts)
    RewriteFrontend.abort_last_request()
    RewriteFrontend.last_request = CurlRequest:new({ body = {}, base_url = "base", endpoint = CompletionsEndpoints.oai_v1_chat_completions, })
    vim.cmd("normal! 0V6jV") -- down 5 lines from current position, 2nd v ends selection ('< and '> marks now have start/end positions)
    vim.cmd("normal! 5k") -- put cursor back before next steps (since I used 5j to move down for end of selection range
    RewriteFrontend.selection = Selection.get_visual_selection_for_current_window()
    RewriteFrontend.accumulated_chunks = ""
    RewriteFrontend.displayer = Displayer:new(RewriteFrontend.accept_rewrite, RewriteFrontend.cleanup_after_cancel)
    RewriteFrontend.displayer:set_keymaps()

    local full_rewrite = RewriteFrontend.selection.original_text .. "\nINSTANT NEW LINE"
    local simulated_sse = {
        choices = { { delta = { content = full_rewrite } } },
        timings = {
            cache_n = 1000,
            predicted_per_second = 120,
            predicted_n = 100,
            prompt_per_second = 200,
            prompt_n = 400,
        }
    }
    RewriteFrontend.on_parsed_data_sse(simulated_sse)
end

---@type ExplainError
function RewriteFrontend.explain_error(text)
    if not RewriteFrontend.displayer then
        vim.notify("ERROR, and no displayer, so here goes: " .. text, vim.log.levels.ERROR)
        return
    end
    vim.schedule(function()
        RewriteFrontend.displayer:explain_error(RewriteFrontend.selection, text)
    end)
end

local function retry_last_rewrite_command()
    if RewriteFrontend.displayer then
        RewriteFrontend.displayer:reject()
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

-- Completion for the AskRewrite command now delegated to the prompts module.

function RewriteFrontend.setup()
    vim.api.nvim_create_user_command(
        "AskRewrite",
        ask_rewrite_command,
        { range = true, nargs = "*", complete = require("ask-openai.predictions.context.prompts").SlashCommandCompletion }
    )

    vim.keymap.set({ 'n', 'v' }, '<Leader>rw', ':<C-u>AskRewrite ', { noremap = true })

    vim.keymap.set({ 'n', 'v' }, '<Leader>ry', retry_last_rewrite_command, { noremap = true })

    -- * simulations
    vim.api.nvim_create_user_command("AskRewriteSimulateInstant", simulate_instant_rewrite_command, {})
    vim.keymap.set({ 'n' }, '<Leader>rt', ':<C-u>AskRewriteSimulateInstant<CR>', { noremap = true })
    --
    vim.api.nvim_create_user_command("AskRewriteSimulateStream", simulate_streaming_rewrite_command, {})
    vim.keymap.set({ 'n' }, '<Leader>rs', ':<C-u>AskRewriteSimulateStream<CR>', { noremap = true })

    -- dump helpers while building this tooling - [a]sk [d]ump last [s]election
    vim.api.nvim_create_user_command("AskDumpLastSelection", buffers.dump_last_seletion_command, {})
    vim.api.nvim_set_keymap('n', '<Leader>ads', ':AskDumpLastSelection<CR>', { noremap = true })
    vim.api.nvim_set_keymap('v', '<Leader>ads', ':<C-u>AskDumpLastSelection<CR>', { noremap = true })

    -- FYI see notes in M.get_visual_selection about you don't want a lua func handler that calls dump
    -- also prints don't popup if they originated in a lua handler, whereas they do with a vim command
    --   thus w/ a cmd I get to see the vim.inspect(selection) with a pprint json like view of fields
end

return RewriteFrontend
