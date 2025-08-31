local M = {}
local log = require("ask-openai.logs.logger").predictions()

local function body_for(prefix, suffix, _recent_edits)
    local body = {
        -- vllm /v1/completions:
        -- https://docs.vllm.ai/en/stable/serving/openai_compatible_server.html#completions-api
        --
        -- vllm FIM discussions:
        --   https://github.com/vllm-project/vllm/pull/11713

        -- prefer base models for codegen, more "EOF" focused/less verbose
        -- list of qwen2.5-coder models:
        --   https://huggingface.co/collections/Qwen/qwen25-coder-66eaa22e6f99801bf65b0c2f
        -- model = "Qwen/Qwen2.5-Coder-7B",
        -- model = "Qwen/Qwen2.5-Coder-7B-Instruct", -- more verbose completions b/c this is chat finetuned model
        -- model = "Qwen/Qwen2.5-Coder-7B", *** favorite
        -- model = "Qwen/Qwen2.5-Coder-1.5B",
        -- model = "Qwen/Qwen2.5-Coder-0.5B",
        --
        -- quantized variants:
        -- model = "Qwen/Qwen2.5-Coder-32B-Instruct-AWQ", -- ~20GB (4GBx5)
        -- model = "Qwen/Qwen2.5-Coder-32B-Instruct-GPTQ-Int8", -- won't fit for me
        -- model = "Qwen/Qwen2.5-Coder-32B-Instruct-GPTQ-Int4", -- SHOULD WORK!


        -- AFAICT, vllm doesn't support prompt(prefix)/suffix params, instead must be fully raw always
        --   their docs explicitly state that they don't support "suffix"
        --   so I'd have to build prompt just like I am doing w/ ollama's /api/generate
        -- raw = true, -- bypass templates (only /api/generate, not /v1/completions)


        stream = true,

        max_tokens = 200,

        -- TODO temperature, top_p,

        -- options = {
        --     -- stop_token_ids: Optional[list[int]] = Field(default_factory=list)  -- vllm
        --     -- any params for parallelization like I had w/ ollama/
        --     --   num_ctx = 8192, -- ollama
        -- }
    }

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


    if string.find(body.model, "codellama") then
        -- codellama template:
        --    {{- if .Suffix }}<PRE> {{ .Prompt }} <SUF>{{ .Suffix }} <MID>
        sentinel_tokens = {
            fim_prefix = "<PRE> ",
            fim_suffix = " <SUF>",
            fim_middle = " <MID>",
        }

        -- codellama uses <EOT> that seems to not be set as param in modelfile (at least for FIM?)
        --   without this change you will see <EOT> in code at end of completions
        -- ollama show codellama:7b-code-q8_0 --parameters # => no stop param
        body.options.stop = { "<EOT>" }

        -- FYI also ollama warns about:
        --    level=WARN source=types.go:512 msg="invalid option provided" option=rope_frequency_base
    elseif not string.find(body.model, "Qwen2.5-Coder", nil, true) then
        -- warn that FIM tokens need to be set
        log:error("PLEASE REVIEW FIM SENTINEL TOKENS FOR THE NEW MODEL! right now you are using sentinel_tokens for qwen2.5-coder")
        return
    end

    -- for now only using body for above logic to check model params
    body.model = nil -- for now don't pass it so I can swap serve on backend and not need to update here


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
    -- *** I was using instruct model, need to repeat test of recent edits with BASE models
    --
    -- local recent_changes = "Here are some recent lines that were edited by the user: "
    -- -- PRN need edits for other files too
    -- for _, change in pairs(recent_edits) do
    --     local str = string.format("Line %d, Column %d: %s", change.lnum, change.col, change.line)
    --     -- todo include line/col or not?
    --     recent_changes = recent_changes .. "\n" .. str
    -- end
    -- raw_prompt = recent_changes .. "\n\n" .. raw_prompt

    body.prompt = raw_prompt




    local body_json = vim.json.encode(body)

    log:trace("body", body_json)

    return body_json
end


function M.build_request(prefix, suffix, recent_edits)
    local options = {
        command = "curl",
        args = {
            "--fail-with-body",
            "-sSL",
            "--no-buffer", -- curl seems to be the culprit... w/o this it batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            "http://ollama:8000/v1/completions", -- TODO pass in api base_url (via config)
            "-H", "Content-Type: application/json",
            "-d", body_for(prefix, suffix, recent_edits)
        },
    }
    return options
end

---@param lines string
---@returns SSEResult
function M.process_sse(lines)
    -- SSE = Server-Sent Event
    -- split on lines first (each SSE can have 0+ "event" - one per line)

    -- TODO probably need to bring over legacy-completions.lua AS it might be closer to openai compat responses from vllm...

    -- FYI use nil to indicate nothing in the SSE... vs empty line which is a valid thingy right?
    local chunk = nil -- combine all chunks into one string and check for done
    local done = false
    local finish_reason = nil
    local stats = nil
    for ss_event in lines:gmatch("[^\r\n]+") do
        if ss_event:match("^data:%s*%[DONE%]$") then
            -- shouldn't land here b/c finish_reason is usually on prior SSE
            return SSEResult:new(chunk, true)
        end

        --  strip leading "data: " (if present)
        local event_json = ss_event
        if ss_event:sub(1, 6) == "data: " then
            -- ollama /api/generate doesn't prefix each SSE with 'data: '
            event_json = ss_event:sub(7)
        end
        local success, parsed_sse = pcall(vim.json.decode, event_json)

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
        if success and parsed_sse and parsed_sse.choices and parsed_sse.choices[1] then
            -- TODO! need to update this to match changes made in backends/llama.lua
            -- TODO! OR just ditch this one and merge any vllm specific parsing concerns into another case in other backend
            local first_choice = parsed_sse.choices[1]
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
            if parsed_sse.timings then
                stats = parse_llamacpp_stats(parsed_sse)
            end
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    return SSEResult:new(chunk, done, finish_reason, stats)
end

return M
