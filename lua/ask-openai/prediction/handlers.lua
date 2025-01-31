local uv = vim.uv
local M = {}
local Prediction = require("ask-openai.prediction.prediction")
local Job = require("plenary.job")

-- FYI would need current prediction PER buffer in the future if want multiple buffers to have predictions at same time (not sure I want this feature)
M.current_prediction = nil -- set on module for now, just so I can inspect it easily

-- FYI useful to observe what is happening under hood, run in pane below nvim (don't need to esc and look at :messages)
--    tail -f /Users/wesdemos/.local/share/nvim/ask/ask-predictions.log
M.logger = require("ask-openai.prediction.logger").predictions()
local function info(...)
    M.logger:log(...)
end
if not require("ask-openai.config").get_options().verbose then
    info = function(...)
        -- no-op
    end
end

-- TODO add unit test of info log method so I don't waste another hour on its quirks:
-- info("foo", nil, "bar") -- use to validate nil args don't interupt the rest of log args getting included -- nuke this is fine, just leaving as a reminder I had trouble with logging nil values

function M.ask_for_prediction()
    M.stop_current_prediction()


    local original_row_1based, original_col = unpack(vim.api.nvim_win_get_cursor(0)) -- (1,0) based #s... aka original_row starts at 1, original_col starts at 0
    local original_row = original_row_1based - 1 -- 0-based now
    -- 100 did not work well here.. with 7b model too 30+ seconds to generate a response! 10 lines works very fast (faster than supermaven) and gives decent responses
    --   PRN race using FIM vs AR (complete) and show first completed suggestion and allow toggle to next?
    -- ... Zed uses 32 (max 64 totallines, 32 before/after by default) => shifted if near top/bottom of doc too
    -- PRN consider (when available) to get the lines back to a meaningful branch in the syntax tree of the code you are editing? does that help?
    local first_row = original_row - 10 -- lets try to take entire document if avail! (in future clip at some key boundary... unsure how that would work best w/ how models are trained on FIM
    local last_row = original_row + 10 -- limit how much we consider past this point? or take it all too?

    -- adjust range so that we maximize context? is this good or not?
    -- FYI I am not sure I like this here... more lines after doesn't likely help much, more lines before may help

    local num_rows_total = vim.api.nvim_buf_line_count(0)
    if first_row < 0 then
        -- TODO write tests of this if I keep it
        info("at start or close: ", first_row)
        last_row = last_row - first_row
        first_row = 0
    elseif last_row >= num_rows_total then
        info("at end or close: ", last_row)
        local past = last_row - num_rows_total + 1
        last_row = num_rows_total - 1
        first_row = first_row - past
        -- todo do I have to ensure > 0 ? for first_row
    end
    info("first_row", first_row, "last_row", last_row)

    local IGNORE_BOUNDARIES = false
    local current_line = vim.api.nvim_buf_get_lines(0, original_row, original_row + 1, IGNORE_BOUNDARIES)[1] -- 0based indexing
    local current_before_cursor = current_line:sub(1, original_col + 1) -- TODO include current cursor slot as before or after?
    local current_after_cursor = current_line:sub(original_col + 2)
    local context_before = vim.api.nvim_buf_get_lines(0, first_row, original_row, IGNORE_BOUNDARIES) -- 0based indexing
    local context_before_text = table.concat(context_before, "\n") .. current_before_cursor
    -- give some instructions in a comment (TODO use comment string to do this)
    local current_buffer_file_name = vim.api.nvim_buf_get_name(0)

    -- use comment string to add a comment with the filename (just basename for now, can get full path too w/o :t)
    -- TODO troubleshoot if there is no commentstring set? how about warn and not set comment header
    local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")
    local comment_header = string.format(vim.o.commentstring, "this from the file named: '" .. filename .. "'\n")
    context_before_text = comment_header .. context_before_text
    -- TODO! go back to raw format and try this BEFORE fim_prefix tag
    info("comment_header: ", comment_header)

    -- TODO get tree of doc code and extract key symbols?

    local context_after = vim.api.nvim_buf_get_lines(0, original_row, last_row, IGNORE_BOUNDARIES) -- 0based indexing
    local context_after_text = current_after_cursor .. table.concat(context_after, "\n")

    -- TODO limit # chars to configurable amount of context
    -- TODO read from config file tmp.predictions
    local tokens_to_clear = "<|endoftext|>" -- TODO USE THIS?
    local fim = {
        enabled = true,
        prefix = "<|fim_prefix|>",
        middle = "<|fim_middle|>",
        suffix = "<|fim_suffix|>",
    }

    -- TODO strip comments? or maybe strip comments marked a certain way? or not marked that way?

    -- TODO provide guidance before fim_prefix... can I just <|im_start|> blah <|im_end|>? (see qwen2.5-coder template for how it might work)
    -- TODO setup separate request/response handlers to work with both /api/generate AND /v1/completions => use config to select which one
    --    TEST w/o deepseek-r1 using api/generate with FIM manual prompt ... which should work ... vs v1/completions for deepseek-r1:7b should fail to FIM or not well

    -- TODO try repo level code completion: https://github.com/QwenLM/Qwen2.5-coder?tab=readme-ov-file#4-repository-level-code-completion
    --    this is not FIM, rather it is like AR... give it <|repo_name|> and then multiple files delimited with <|file_sep|> and name and then contents... then last file is only partially complete (it generates the rest of it)
    -- The more I think about it, the less often I think I use the idea of FIM... I really am just completing (often w/o a care for what comes next)... should I be trying non-FIM too? (like repo level completions?)
    -- PSM inference format:
    -- local raw_prompt = fim.prefix .. context_before_text .. fim.suffix .. context_after_text .. fim.middle

    -- TODOs
    --   include outline/symbols for current doc
    --   include recent edits? (other files too) and maybe the symbol edited (i.e. func)
    --   include filename (thus language)
    --   include preamble request of what to do? <|im_start|> section?

    local body = {
        -- !!! TODO migrate to /v1/completions "legacy" OpenAI completions endpoint (also has RAW prompt)
        --    ollama supports it: https://github.com/ollama/ollama/blob/main/docs/openai.md#v1completions
        --    for FIM, you won't likely use /chat/completions (two different tasks and models are trained on FIM alone, not w/ chat messages in prompt)
        --
        model = "qwen2.5-coder:7b", --0.5b, 1b, 3b*, 7b, 14b*, 32b
        -- TODO try deepseek-coder-v2 (MOE 16b model)

        -- model = "codellama:7b-code-q4_K_M", -- FYI only -code models have PSM in template? or is that a mistake in some of the -instruct models... I thought instruct had infill?
        -- btw => codellama:-code uses: <PRE> -- calculator\nlocal M = {}\n\nfunction M.add(a, b)\n    return a + b\nend1 <SUF>1\n\n\n\nreturn M <MID>
        --      Admittedly it is nice to switch models and have the template handle the FIM token differences...

        -- *** prompt differs per endpoint:
        -- -- ollama's /api/generate, also IIAC everyone else's /v1/completions:
        -- prompt = raw_prompt
        --
        -- ollama's /v1/completions + Templates (I honestly hate this... you should've had a raw flag in your /v1/completions implementation... why fuck over all users?)
        --     btw ollama discusses templating for FIM here: https://github.com/ollama/ollama/blob/main/docs/template.md#example-fill-in-middle
        prompt = context_before_text, -- ollama's /v1/completions + qwen2.5-coder's template (and their guidance on FIM)
        suffix = context_after_text,
        -- I AM TEMPTED TO JUST USE /api/generate so I don't get f'ed over by the template in ollama... but let me wait for that to happen first
        -- TODO add logic to switch the request/response parsing based on backend and vs not
        raw = true, -- ollama's /api/generate allows to bypass templates... unfortunately, ollama doesn't have this param for its /v1/completions endpoint

        stream = true,
        -- num_predict = 40, -- max tokens for ollama's /api/generate
        max_tokens = 40,
        -- TODO roll up the request building into separate classes, and response parsing too.. so its /api/generate or /chat/completions specific w/o needing consumer to think much about it
        -- TODO temperature, top_p,
    }

    local body_serialized = vim.json.encode(body)
    -- info("body", body_serialized)

    local options = {
        command = "curl",
        args = {
            "-fsSL",
            "--no-buffer", -- curl seems to be the culprit... w/o this it batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            "http://ollama:11434/v1/completions",
            -- "http://ollama:11434/api/generate",
            "-H", "Content-Type: application/json",
            "-d", body_serialized
        },
        -- TODO do I need to set stream job option? (plenary.curl uses this to decide if it wires up on_stdout... but I don't think its needed w/ plenary.job alone?) unsure... works w/o it so far
        -- stream = true
    }

    -- log the curl call, super useful for testing independently in terminal
    -- info("curl", table.concat(options.args, " "))

    -- closure captures this id for any callbacks to use to ignore past predictions
    local this_prediction = Prediction:new()
    M.current_prediction = this_prediction

    -- FYI if any issues with plenary.job, it was super easy to use uv.spawn, w/ new_pipe(s):
    --    git show 21d1e11  -- this commit is when I changed to plenary
    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)
    -- Plenary adds some features that aren't there that might cause issues..
    --   or might help, i.e. it looks like it combines chunks / splits on new lines? I need to re-read the code but I thought I saw that:
    --      https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/job.lua#L285 on_output
    --   this might be useful, but if it causes issues then go back to uv.spawn...
    --   also, AFAIK with SSE events, the protocol has each event as a separate chunk (not split up across chunks) so I don't think I have a need for what on_output does..
    --   also if plenary.job adds overhead then remove it too...
    --   TODO read entirety of plenary.job and see if I really want to use it (measure timing if needed)...
    --     also check out plenary.curl which might have added features for my use case that will help over plenary.job alone (plenary.curl is built on plenary.job)

    options.on_exit = function(code, signal) -- uv.spawn
        info("spawn - exit code:", code, "Signal:", signal)
        stdout:close()
        stderr:close()
    end

    -- M.handle, M.pid = uv.spawn("fish", {
    -- args = { "-c", "echo foo;" },
    M.handle, M.pid = uv.spawn(options.command, {
        args = options.args,
        stdio = { nil, stdout, stderr },
    }, options.on_exit)


    -- options.on_exit = function(job, code, signal) -- plenary.job
    --     info("on_exit code:", vim.inspect(code), "Signal:", signal)
    --     if code ~= 0 then
    --         this_prediction:mark_generation_failed()
    --     else
    --         this_prediction:mark_generation_finished()
    --     end
    -- end

    local function process_sse(data)
        -- TODO add some tests of this parsing? can run outside of nvim too
        -- SSE = Server-Sent Event
        -- split on lines first (each SSE can have 0+ "event" - one per line)

        -- FYI use nil to indicate nothing in the SSE... vs empty line which is a valid thingy right?
        local chunk = nil -- combine all chunks into one string and check for done
        local done = false
        for ss_event in data:gmatch("[^\r\n]+") do
            if ss_event:match("^data:%s*%[DONE%]$") then
                -- done, courtesy last event... mostly ignore b/c finish_reason already comes on the prior SSE
                return chunk, true
            end

            --  strip leading "data: " (if present)
            local event_json = ss_event
            if ss_event:sub(1, 6) == "data: " then
                -- ollama /api/generate doesn't prefix each SSE with 'data: '
                event_json = ss_event:sub(7)
            end
            local success, parsed = pcall(vim.json.decode, event_json)

            -- *** /v1/completions
            if success and parsed.choices and parsed.choices[1] and parsed.choices[1].text then
                local choice = parsed.choices[1]
                local text = choice.text
                if choice.finish_reason == "stop" then -- TODO "length"?
                    done = true
                elseif choice.finish_reason == "length" then
                    -- got this reason when testing
                    -- max len?
                    done = true
                elseif choice.finish_reason ~= vim.NIL then
                    info("WARN - unexpected /v1/completions finish_reason: ", choice.finish_reason, " do you need to handle this too?")
                    -- ok for now to continue too
                    done = true
                end
                chunk = (chunk or "") .. text

                -- -- *** ollama format for /api/generate, examples:
                -- --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.1915236Z","response":"\n","done":false}
                -- --  done example:
                -- --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.2800621Z","response":"","done":true,"done_reason":"stop","total_duration":131193100,"load_duration":16550700,"prompt_eval_count":19,"prompt_eval_duration":5000000,"eval_count":12,"eval_duration":106000000}
                -- if success and parsed and parsed.response then
                --     if parsed.done then
                --         local done_reason = parsed.done_reason
                --         done = true
                --         if done_reason ~= "stop" then
                --             info("WARN - unexpected /api/generate done_reason: ", done_reason, " do you need to handle this too?")
                --             -- ok for now to continue too
                --         end
                --     end
                --     chunk = (chunk or "") .. parsed.response
            else
                info("SSE json parse failed for ss_event: ", ss_event)
            end
        end
        return chunk, done
    end

    options.on_stdout = function(err, data) -- uv.spawn
        -- options.on_stdout = function(err, data, job) -- plenary.job
        info("on_stdout data: ", data, "err: ", err)
        -- FYI, with plenary.job, on_stdout/on_stderr are both called one last time (with nil data) after :shutdown is called... NBD just a reminder
        if err then
            this_prediction:mark_generation_failed()
            return
        end
        if data then
            vim.schedule(function()
                local chunk, generation_done = process_sse(data)
                if chunk then
                    this_prediction:add_chunk_to_prediction(chunk)
                end
                if generation_done then
                    this_prediction:mark_generation_finished()
                end
            end)
        end
    end
    uv.read_start(stdout, options.on_stdout) -- must call AFTER spawn

    options.on_stderr = function(err, data) -- uv.spa
        -- options.on_stderr = function(err, data, job) -- plenary.job
        -- FYI, with plenary.job, on_stdout/on_stderr are both called one last time (with nil data) after :shutdown is called... NBD just a reminder
        -- just log for now is fine
        -- DO NOT USE "data:" b/c that is what each streaming chunk is prefixed with and so confuses the F out of me when I see that and think oh its fine... nope
        info("on_stderr chunk: ", data, "err: ", err)
        if err then
            -- TODO stop abort?
        end
    end
    uv.read_start(stderr, options.on_stderr) -- must call AFTER spawn

    -- M.request = Job:new(options)
    -- M.request:start()
end

function M.stop_current_prediction()
    local this_prediction = M.current_prediction
    if not this_prediction then
        return
    end
    M.current_prediction = nil
    this_prediction:mark_as_abandoned()

    vim.schedule(function()
        this_prediction:clear_extmarks()
    end)

    local handle = M.handle
    local pid = M.pid
    M.handle = nil
    -- M.request = nil -- plenary.job
    M.pid = nil
    if handle ~= nil and not handle:is_closing() then
        info("Terminating process, pid: ", pid)

        handle:kill("sigterm")
        handle:close()
        -- FYI ollama should log => "aborting completion request due to client closing the connection"

        -- FYI I can kill the plenary job myself too using its handle/pid
        -- request:shutdown() -- FYI request:handle():kill("sigterm") or similar should work w/ plenary.job
        --  -- :shutdown() doesn't terminate curl calls, they all complete after ollama serially serves them!
    end
end

-- todo help/readonly buffers?
local ignore_filetypes = {
    "TelescopePrompt",
    "NvimTree",
    "DressingInput", -- pickers from nui (IIRC) => in nvim tree add a file => the file name box is one of these
    -- TODO make sure only check this on enter buffer first time? not on every event (cursormoved,etc)

    -- TODO consider these exclusions too (per chatgpt)
    -- "spectre_panel", -- Find and replace UI (nvim-spectre)
    -- "noice", -- Noice.nvim popups
    -- "lazy", -- Lazy.nvim plugin manager UI (these are all readonly IIAC so I could ignore on readonly?)
    -- "mason", -- Mason.nvim UI
    -- "lspinfo", -- LSP info window
    -- "toggleterm", -- Terminal UI
    -- "dap-repl", -- Debugging REPL
    -- "dapui_watches", "dapui_stacks", "dapui_scopes", "dapui_breakpoints", -- DAP UI components
    -- "alpha", -- Dashboard (alpha.nvim)
    -- "help", -- Help buffers
    -- "man", -- Man pages
    -- "qf", -- Quickfix list
    -- "prompt", -- Generic prompt filetype
    -- "fugitive", "gitcommit", "NeogitStatus", -- Git status/rebase windows
    -- "starter", -- Some dashboard plugins use this
}

local ignore_buftypes = {
    "nofile", -- rename refactor popup window uses this w/o a filetype, also Dressing rename in nvimtree uses nofile

    -- maybes:
    -- vim.bo.buftype == "terminal" -- Ignore terminal windows
    -- vim.bo.buftype == "prompt" -- UI input prompts
    -- vim.bo.buftype == "quickfix" -- Quickfix and location list
    -- vim.bo.readonly -- Read-only buffers (optional)
}

--
local rx = require("rx")
local TimeoutScheduler = require("ask-openai.rx.scheduler")
local scheduler = TimeoutScheduler.create()
local keypresses = rx.Subject.create()
local debounced = keypresses:debounce(250, scheduler)
local sub = debounced:subscribe(function()
    vim.schedule(function()
        info("CursorMovedI debounced")

        -- YES! now this is how I can stop predictions, i can exit insert mode and stop altogether
        -- TODO move into observable? filter?
        if vim.fn.mode() ~= "i" then return end

        M.ask_for_prediction()
    end)
end)
--TODO on exit... sub:unsubscribe()... not needed... not sure if I ever need it to be disabled...
--
--PRN this should be per buffer at some point... could add buffer to onNext({buffer=1}) ... and use groupby/debounce to handle all of that yummyness in the event stream

-- separate the top level handlers -> keep these thin so I can distinguish the request from the work (above)
function M.cursor_moved_in_insert_mode()
    -- TODO DEBOUNCE TYPING USING RXLUA like I did with mouse thingy => only after say 3 keys then start debouncing so further typing isn't jarring

    if M.current_prediction ~= nil and M.current_prediction.disable_cursor_moved == true then
        info("Disabled CursorMovedI, skipping...")
        M.current_prediction.disable_cursor_moved = false -- re-enable it, just skip one time... yes it sucks
        -- basically this is called after accepting/inserting the new content (AFAICT only one time too)
        return
    end

    if vim.tbl_contains(ignore_buftypes, vim.bo.buftype)
        or vim.tbl_contains(ignore_filetypes, vim.bo.filetype) then
        return
    end

    -- M.ask_for_prediction() -- move this to observer
    keypresses:onNext({}) -- TODO any data to pass?
end

function M.leaving_insert_mode()
    M.stop_current_prediction()
end

function M.entering_insert_mode()
    print("function M.entering_insert_mode()")

    -- TODO anything specific to entering insert mode?
    M.cursor_moved_in_insert_mode()
end

function M.accept_all_invoked()
    info("Accepting all predictions...")
    if not M.current_prediction then
        return
    end
    M.current_prediction:accept_all()
end

function M.accept_line_invoked()
    info("Accepting line prediction...")
    if not M.current_prediction then
        return
    end
    M.current_prediction:accept_first_line()
end

function M.accept_word_invoked()
    info("Accepting word prediction...")
    if not M.current_prediction then
        return
    end
    M.current_prediction:accept_first_word()
end

function M.vim_is_quitting()
    -- just in case, though leaving insert mode should already do this
    info("Vim is quitting, stopping current prediction...")
    M.stop_current_prediction()
end

return M
