local M = {}
local log = require("ask-openai.prediction.logger").predictions()
_G.PLAIN_FIND = true

local function body_for(prefix, suffix, _recent_edits)

    -- IDEA - pass param sets in to make model specific alterations
    local agentica_params = {
        -- https://huggingface.co/agentica-org/DeepCoder-14B-Preview#usage-recommendations


    }



    local body = {
        -- TODO! generalize backend for chat completions (rewrites, asks, etc) - and/or - 'legacy' /completions... each should probably have its own backend
        --   TODO maybe even absorb ollama chat completions?

        -- TODO which to use /completions or /chat/completions
        -- /completions https://docs.vllm.ai/en/stable/serving/openai_compatible_server.html#completions-api
        -- /chat/completions: https://docs.vllm.ai/en/stable/serving/openai_compatible_server.html#chat-api

        -- agentica-org models
        -- fine tune of deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B
        model = "agentica-org/DeepCoder-1.5B-Preview", -- reminder as vllm serve dictates the model
        -- https://huggingface.co/mradermacher/DeepCoder-1.5B-Preview-GGUF - quantizeds

        -- model = "Qwen/Qwen2.5-Coder-7B-Instruct",
        --
        -- quantized variants:
        -- model = "Qwen/Qwen2.5-Coder-32B-Instruct-AWQ", -- ~20GB (4GBx5)
        -- model = "Qwen/Qwen2.5-Coder-32B-Instruct-GPTQ-Int8", -- won't fit for me
        -- model = "Qwen/Qwen2.5-Coder-32B-Instruct-GPTQ-Int4", -- SHOULD WORK!

        stream = true,

        max_tokens = 400,

        -- TODO temperature, top_p,

        -- options = {
        --     -- stop_token_ids: Optional[list[int]] = Field(default_factory=list)  -- vllm
        --     -- any params for parallelization like I had w/ ollama/
        --     --   num_ctx = 8192, -- ollama
        -- }
    }

    -- TODO do any of these work in chat completions API? IIRC <|im_end|> might, I saw it with tool use instructions, IIRC
    local sentinel_tokens = {
        -- qwen2.5-coder:
        fim_prefix = "<|fim_prefix|>",
        fim_middle = "<|fim_middle|>",
        fim_suffix = "<|fim_suffix|>",
        -- fim_pad = "<|fim_pad|>",
        repo_name = "<|repo_name|>",
        file_sep = "<|file_sep|>",
        im_start = "<|im_start|>",
        im_end = "<|im_end|>",
        -- todo others?
        -- endoftext = "<|endoftext|>"
    }

    -- TODO MESSAGES
    -- body.messages = ?


    local body_json = vim.json.encode(body)

    log:trace("body", body_json)

    return body_json
end


function M.build_request(prefix, suffix, recent_edits)
    local options = {
        command = "curl",
        args = {
            "-fsSL",
            "--no-buffer", -- curl seems to be the culprit... w/o this it batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            "http://ollama:8000/v1/completions", -- TODO pass in api base_url (via config)
            "-H", "Content-Type: application/json",
            "-d", body_for(prefix, suffix, recent_edits)
        },
    }
    return options
end

function M.process_sse(data)
    -- SSE = Server-Sent Event
    -- split on lines first (each SSE can have 0+ "event" - one per line)

    -- TODO probably need to bring over legacy-completions.lua AS it might be closer to openai compat responses from vllm...

    -- FYI use nil to indicate nothing in the SSE... vs empty line which is a valid thingy right?
    local chunk = nil -- combine all chunks into one string and check for done
    local done = false
    local finish_reason = nil
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

        -- *** examples /api/generate:
        --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.1915236Z","response":"\n","done":false}
        --  done example:
        --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.2800621Z","response":"","done":true,"done_reason":"stop","total_duration":131193100,"load_duration":16550700,"prompt_eval_count":19,"prompt_eval_duration":5000000,"eval_count":12,"eval_duration":106000000}

        -- *** vllm /v1/completions responses:
        --  middle completion:
        --   {"id":"cmpl-eec6b2c11daf423282bbc9b64acc8144","object":"text_completion","created":1741824039,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":"ob","logprobs":null,"finish_reason":null,"stop_reason":null}],"usage":null}
        --
        --  final completion:
        --   {"id":"cmpl-06be557c45c24e458ea2e36d436faf60","object":"text_completion","created":1741823318,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":" and","logprobs":null,"finish_reason":"length","stop_reason":null}],"usage":null}
        --    pretty print with vim:
        --    :Dump(vim.json.decode('{"id":"cmpl-06be557c45c24e458ea2e36d436faf60","object":"text_completion","created":1741823318,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":" and","logprobs":null,"finish_reason":"length","stop_reason":null}],"usage":null}')
        -- {
        --   choices = { {
        --       finish_reason = "length",
        --       index = 0,
        --       logprobs = vim.NIL,
        --       stop_reason = vim.NIL,
        --       text = " and"
        --     } },
        --   created = 1741823318,
        --   id = "cmpl-06be557c45c24e458ea2e36d436faf60",
        --   model = "Qwen/Qwen2.5-Coder-3B",
        --   object = "text_completion",
        --   usage = vim.NIL
        -- }

        -- log:info("success:", success)
        -- log:info("choices:", vim.inspect(parsed))
        -- log:info("choices:", vim.inspect(parsed.choices))
        if success and parsed and parsed.choices and parsed.choices[1] then
            local first_choice = parsed.choices[1]
            finish_reason = first_choice.finish_reason
            if finish_reason ~= nil and finish_reason ~= vim.NIL then
                log:info("finsh_reason: ", finish_reason)
                done = true
                if finish_reason ~= "stop" and finish_reason ~= "length" then
                    log:warn("WARN - unexpected finish_reason: ", finish_reason, " do you need to handle this too?")
                end
            end
            if first_choice.text == nil then
                log:warn("WARN - unexpected, no choice in completion, do you need to add special logic to handle this?")
            else
                chunk = (chunk or "") .. first_choice.text
            end
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    -- TODO test passing back finish_reason (i.e. for an empty prediction log entry)
    return chunk, done, finish_reason
end

return M
