local M = {}
local log = require("ask-openai.prediction.logger").predictions()
local qwen = require("ask-openai.backends.models.qwen")
local meta = require("ask-openai.backends.models.meta")

_G.PLAIN_FIND = true
-- TODO can I define an interface in lua?
--    then use a backend variable in handlers.lua... w/ completion regardless of backend
--       local backend = require("../backends/x")

local function body_for(prefix, suffix, _recent_edits)
    local body = {

        -- FYI set of possible models for demoing impact of fine tune
        model = "qwen2.5-coder:14b-base-q8_0", -- ** shorter responses, more "EOF" focused
        -- model = "qwen2.5-coder:7b-base-q8_0", -- ** shorter responses, more "EOF" focused
        -- model = "qwen2.5-coder:7b-instruct-q8_0", -- longer, long winded, often seemingly ignores EOF
        --
        -- model = "codellama:7b-code-q8_0", -- shorter too
        -- model = "codellama:7b-instruct-q8_0", -- longer too
        -- model = "codellama:7b-python-q8_0", -- doesn't do well with FIM (spits out FIM tokens text as if not recognized)... also not sure it supports FIM based on reading docs only code/instruct are mentioned for FIM support)
        --
        -- model = "llama3.1:8b-text-q8_0", -- weird, generated some "code"/text in this file that wasn't terrible!... verbose
        -- model = "llama3.1:8b-instruct-q8_0", --
        -- https://github.com/meta-llama/codellama/blob/main/llama/generation.py#L496



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

    local sentinel_tokens = qwen.qwen25coder.sentinel_tokens

    if string.find(body.model, "codellama") then
        sentinel_tokens = meta.codellama.sentinel_tokens

        -- codellama uses <EOT> that seems to not be set as param in modelfile (at least for FIM?)
        --   without this change you will see <EOT> in code at end of completions
        -- ollama show codellama:7b-code-q8_0 --parameters # => no stop param
        body.options.stop = { "<EOT>" }

        -- FYI also ollama warns about:
        --    level=WARN source=types.go:512 msg="invalid option provided" option=rope_frequency_base
    elseif not string.find(body.model, "qwen2.5-coder", nil, _G.PLAIN_FIND) then
        -- warn that FIM tokens need to be set
        log:error("PLEASE REVIEW FIM SENTINEL TOKENS FOR THE NEW MODEL! right now you are using sentinel_tokens for qwen2.5-coder")
        return
    end


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
    local recent_changes = "Here are some recent lines that were edited by the user: "
    -- -- PRN need edits for other files too
    for _, change in pairs(recent_edits) do
        local str = string.format("Line %d, Column %d: %s", change.lnum, change.col, change.line)
        -- todo include line/col or not?
        recent_changes = recent_changes .. "\n" .. str
    end
    raw_prompt = recent_changes .. "\n\n" .. raw_prompt

    body.prompt = raw_prompt




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
    local done_reason = nil
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
                done_reason = parsed.done_reason
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
    -- TODO test passing back finish_reason (i.e. for an empty prediction log entry)
    return chunk, done, done_reason
end

return M
