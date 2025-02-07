local M = {}
local log = require("ask-openai.prediction.logger").predictions()

-- TODO can I define an interface in lua?
--    then use a backend variable in handlers.lua... w/ completion regardless of backend
--       local backend = require("../backends/x")

local function body_for(prefix, suffix, recent_edits)
    local sentinel_tokens = {
        fim_prefix = "<|fim_prefix|>",
        fim_middle = "<|fim_middle|>",
        fim_suffix = "<|fim_suffix|>",
        fim_pad = "<|fim_pad|>",
        repo_name = "<|repo_name|>",
        file_sep = "<|file_sep|>",
        im_start = "<|im_start|>",
        im_end = "<|im_end|>",

        -- todo others?
        -- endoftext = "<|endoftext|>"
    }

    -- PRN TEST w/o deepseek-r1 using api/generate with FIM manual prompt
    --   IIRC template is wrong but it does support FIM?

    -- TODO provide guidance before fim_prefix...
    --   can I just <|im_start|> blah <|im_end|>?
    --   see qwen2.5-coder template for how it might work

    -- TODO try repo level code completion:
    --   https://github.com/QwenLM/Qwen2.5-coder?tab=readme-ov-file#4-repository-level-code-completion
    --   this is not FIM, rather it is like AR:
    --     give it <|repo_name|>
    --     then multiple files
    --       delimited with <|file_sep|> and name
    --     then contents...
    --     then last file is only partially complete
    --       this is what the model is supposed to generate (in its entirely IIRC)
    --       OR, can I make this last file a FIM?
    --         so it just generates middle of last file
    --
    -- The more I think about it, the less often I think I use the idea of FIM...
    --   I often am just completing (often w/o a care for what comes next)...
    --   should I be trying non-FIM too? (like repo level completions?)

    -- PSM inference format:
    log:trace("prefix", "'" .. prefix .. "'")
    log:trace("suffix", "'" .. suffix .. "'")



    -- TODO ESCAPE presence of any sentinel tokens! i.e. should be rare but if someone is working on LLM code it may not be!
    local raw_prompt = sentinel_tokens.fim_prefix .. prefix .. sentinel_tokens.fim_suffix .. suffix .. sentinel_tokens.fim_middle

    -- Edit history totally messed up FIM... how can I include this while preserving the FIM request...
    --   i.e. in calc.lua... it just chatted to me and that's an easy FIM task
    --
    -- local recent_changes = "Here are some recent lines that were edited by the user: "
    -- -- PRN need edits for other files too
    -- for _, change in pairs(recent_edits) do
    --     local str = string.format("Line %d, Column %d: %s", change.lnum, change.col, change.line)
    --     -- todo include line/col or not?
    --     recent_changes = recent_changes .. "\n" .. str
    -- end
    -- raw_prompt = recent_changes .. "\n\n" .. raw_prompt

    local body = {

        model = "qwen2.5-coder:7b-instruct-q8_0",

        prompt = raw_prompt,
        raw = true, -- bypass templates (only /api/generate, not /v1/completions)

        stream = true,
        num_predict = 200, -- aka max_tokens

        -- TODO temperature, top_p,

        options = {
            -- https://github.com/ollama/ollama/blob/main/docs/api.md#generate-request-with-options
            -- options only for /api/generate
            --   /v1/completions ignores them even though it uses same GenerateHandler!

            -- TODO can I pass OLLAMA_NUM_PARALLEL=1 via request?
            num_ctx = 8192,
        }
    }

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
            "http://ollama:11434/api/generate", -- TODO pass in api base_url (via config)
            "-H", "Content-Type: application/json",
            "-d", body_for(prefix, suffix, recent_edits)
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
