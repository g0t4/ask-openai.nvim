local M = {}
local log = require("ask-openai.prediction.logger").predictions()

-- TODO can I define an interface in lua?
--    then use a backend variable in handlers.lua... w/ completion regardless of backend
--       local backend = require("../backends/x")

-- FYI only needed for raw prompts:
local tokens_to_clear = "<|endoftext|>"
local fim = {
    enabled = true,
    prefix = "<|fim_prefix|>",
    middle = "<|fim_middle|>",
    suffix = "<|fim_suffix|>",
}

-- TODO provide guidance before fim_prefix... can I just <|im_start|> blah <|im_end|>? (see qwen2.5-coder template for how it might work)
-- TODO setup separate request/response handlers to work with both /api/generate AND /v1/completions => use config to select which one
--    TEST w/o deepseek-r1 using api/generate with FIM manual prompt ... which should work ... vs v1/completions for deepseek-r1:7b should fail to FIM or not well

-- TODO try repo level code completion: https://github.com/QwenLM/Qwen2.5-coder?tab=readme-ov-file#4-repository-level-code-completion
--    this is not FIM, rather it is like AR... give it <|repo_name|> and then multiple files delimited with <|file_sep|> and name and then contents... then last file is only partially complete (it generates the rest of it)
-- The more I think about it, the less often I think I use the idea of FIM... I really am just completing (often w/o a care for what comes next)... should I be trying non-FIM too? (like repo level completions?)
-- PSM inference format:
-- local raw_prompt = fim.prefix .. context_before_text .. fim.suffix .. context_after_text .. fim.middle

local function body_for(prefix, suffix)
    local body = {
        --
        model = "fim_qwen:7b-instruct-q8_0", -- qwen2.5-coder, see Modelfile
        --
        -- model = "qwen2.5-coder:7b-instruct-q8_0",
        -- model = "qwen2.5-coder:3b-instruct-q8_0", -- trouble paying attention to suffix... and same with prefix... on zedraw functions
        -- model = "qwen2.5-coder:7b", --0.5b, 1b, 3b*, 7b, 14b*, 32b
        -- model = "qwen2.5-coder:7b-instruct-q8_0",
        -- model = "qwen2.5-coder:14b-instruct-q8_0", -- works well if I can make sure nothing else is using up GPU space
        --
        -- *** deepseek-coder-v2 (MOE 16b model)
        --   FYI prompt has template w/ PSM!
        --       ollama show --template deepseek-coder-v2:16b-lite-instruct-q8_0
        -- model = "deepseek-coder-v2:16b-lite-instruct-q8_0", -- *** 34 tokens/sec! almost fits in GPU (4GB to cpu,14 GPU)... very fast for this size... must be MOE activation?
        --   shorter responses and did seem to try to connect to start of suffix, maybe? just a little bit of initial testing
        --   more intelligent?... clearly could tell when similiar file started to lean toward java (and so it somewhat ignored *.cpp filename but that wasn't necessarily wrong as there were missing things (; syntax errors if c++)
        --
        -- model = "codellama:7b-code-q8_0", -- `code` and `python` have FIM, `instruct` does not
        --       wow... ok this model is dumb.. nevermind I put "cpp" in the comment at the top... it only generates java... frustrating...
        --       keeps generating <EOT> in output ... is the template wrong?... at the spot where it would be EOT... in fact it stops at that time too... OR its possible llama has the wrong token marked for EOT and isn't excluding it when it should be
        --       so far, aggresively short completions
        -- btw => codellama:-code uses: <PRE> -- calculator\nlocal M = {}\n\nfunction M.add(a, b)\n    return a + b\nend1 <SUF>1\n\n\n\nreturn M <MID>

        -- *** prompt differs per endpoint:
        -- -- ollama's /api/generate, also IIAC everyone else's /v1/completions:
        -- prompt = raw_prompt
        --
        -- ollama's /v1/completions + Templates (I honestly hate this... you should've had a raw flag in your /v1/completions implementation... why fuck over all users?)
        --     btw ollama discusses templating for FIM here: https://github.com/ollama/ollama/blob/main/docs/template.md#example-fill-in-middle
        prompt = prefix,
        suffix = suffix,
        -- TODO verify do not need raw for v1/completions
        raw = true, -- ollama's /api/generate allows to bypass templates... unfortunately, ollama doesn't have this param for its /v1/completions endpoint

        stream = true,
        -- num_predict = 40, -- /api/generate
        max_tokens = 200,
        -- TODO temperature, top_p,

        -- options = {
        --     /api/generate only
        --        https://github.com/ollama/ollama/blob/main/docs/api.md#generate-request-with-options
        --     --    OLLAMA_NUM_PARALLEL=1 -- TODO can this be passed in /api/generate?
        --     num_ctx = 8192, -- /api/generate only
        -- }
    }

    return vim.json.encode(body)
end


function M.build_request(prefix, suffix)
    local options = {
        command = "curl",
        args = {
            "-fsSL",
            "--no-buffer", -- curl seems to be the culprit... w/o this it batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            "http://ollama:11434/api/generate", -- TODO pass in api base_url (via config)
            "-H", "Content-Type: application/json",
            "-d", body_for(prefix, suffix)
        },
    }
    return options
end


function M.process_sse(data)
    -- TODO tests of parsing?
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
            if choice.finish_reason == "stop" then
                done = true
            elseif choice.finish_reason == "length" then
                done = true
            elseif choice.finish_reason ~= vim.NIL then
                log:warn("WARN - unexpected /v1/completions finish_reason: ", choice.finish_reason, " do you need to handle this too?")
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
            --             log:warn("WARN - unexpected /api/generate done_reason: ", done_reason, " do you need to handle this too?")
            --             -- ok for now to continue too
            --         end
            --     end
            --     chunk = (chunk or "") .. parsed.response
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    return chunk, done
end

return M

