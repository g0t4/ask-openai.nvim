local M = {}
local log = require("ask-openai.prediction.logger").predictions()

-- TODO can I define an interface in lua?
--    then use a backend variable in handlers.lua... w/ completion regardless of backend
--       local backend = require("../backends/x")

local function body_for(prefix, suffix)
    -- FYI only needed for raw prompts:
    local tokens_to_clear = "<|endoftext|>"
    local fim = {
        enabled = true,
        prefix = "<|fim_prefix|>",
        middle = "<|fim_middle|>",
        suffix = "<|fim_suffix|>",
    }

    -- PRN TEST w/o deepseek-r1 using api/generate with FIM manual prompt ... which should work ... vs v1/completions for deepseek-r1:7b should fail to FIM or not well

    -- TODO provide guidance before fim_prefix... can I just <|im_start|> blah <|im_end|>? (see qwen2.5-coder template for how it might work)

    -- TODO try repo level code completion: https://github.com/QwenLM/Qwen2.5-coder?tab=readme-ov-file#4-repository-level-code-completion
    --    this is not FIM, rather it is like AR... give it <|repo_name|> and then multiple files delimited with <|file_sep|> and name and then contents... then last file is only partially complete (it generates the rest of it)
    -- The more I think about it, the less often I think I use the idea of FIM... I really am just completing (often w/o a care for what comes next)... should I be trying non-FIM too? (like repo level completions?)

    -- PSM inference format:
    local raw_prompt = fim.prefix .. prefix .. fim.suffix .. suffix .. fim.middle

    local body = {

        model = "qwen2.5-coder:7b-instruct-q8_0",

        prompt = raw_prompt,
        raw = true, -- bypass templates (only /api/generate, not /v1/completions)

        stream = true,
        num_predict = 200, -- aka max_tokens

        -- TODO temperature, top_p,

        options = {
            -- https://github.com/ollama/ollama/blob/main/docs/api.md#generate-request-with-options
            -- TODO can I pass OLLAMA_NUM_PARALLEL=1 via request?
            num_ctx = 8192, -- /api/generate only
        }
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

        -- *** examples /api/generate:
        --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.1915236Z","response":"\n","done":false}
        --  done example:
        --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.2800621Z","response":"","done":true,"done_reason":"stop","total_duration":131193100,"load_duration":16550700,"prompt_eval_count":19,"prompt_eval_duration":5000000,"eval_count":12,"eval_duration":106000000}
        if success and parsed and parsed.response then
            if parsed.done then
                local done_reason = parsed.done_reason
                done = true
                if done_reason ~= "stop" then
                    log:warn("WARN - unexpected /api/generate done_reason: ", done_reason, " do you need to handle this too?")
                    -- ok for now to continue too
                end
            end
            chunk = (chunk or "") .. parsed.response
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    return chunk, done
end

return M
