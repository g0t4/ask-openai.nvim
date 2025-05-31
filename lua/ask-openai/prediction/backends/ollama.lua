local log = require("ask-openai.prediction.logger").predictions()
local CurrentContext = require("ask-openai.prediction.context")
local fim = require("ask-openai.backends.models.fim")
local meta = require("ask-openai.backends.models.meta")

---@class OllamaFimBackend
---@field prefix string
---@field suffix string
---@field current_context CurrentContext
local OllamaFimBackend = {}
OllamaFimBackend.__index = OllamaFimBackend

---@param prefix string
---@param suffix string
---@return OllamaFimBackend
function OllamaFimBackend:new(prefix, suffix)
    local instance = {
        prefix = prefix,
        suffix = suffix,
        current_context = CurrentContext:new(),
    }
    setmetatable(instance, self)
    return instance
end

function OllamaFimBackend:request_options()
    local options = {
        command = "curl",
        args = {
            "--fail-with-body",
            "-sSL",
            "--no-buffer", -- test w/ `curl *` vs `curl * | cat`
            "-X", "POST",
            "http://ollama:11434/api/generate",
            "-H", "Content-Type: application/json",
            "-d", self:body_for(),
        },
    }
    return options
end

function OllamaFimBackend:body_for()
    local body = {

        -- https://huggingface.co/collections/JetBrains/mellum-68120b4ae1423c86a2da007a
        model = "huggingface.co/JetBrains/Mellum-4b-base-gguf",
        -- model = "huggingface.co/JetBrains/Mellum-4b-sft-python-gguf", -- TODO TRY!
        -- kotlin exists but no gguf on hf yet:
        --   https://huggingface.co/JetBrains/Mellum-4b-sft-kotlin
        -- TODO add in other fine tunes for languages as released

        -- FYI set of possible models for demoing impact of fine tune
        -- qwen2.5-coder:7b-base-q8_0  -- ** shorter responses, more "EOF" focused
        -- qwen2.5-coder:14b-base-q8_0 -- ** shorter responses, more "EOF" focused
        -- qwen2.5-coder:7b-instruct-q8_0 -- DO NOT USE instruct
        -- model = "qwen2.5-coder:7b-base-q8_0",

        -- starcoder2:15b-instruct-v0.1-q8_0                      a11b58c111d9    16 GB     6 weeks ago
        -- starcoder2:15b-q8_0                                    95f55571067f    16 GB     6 weeks ago
        -- starcoder2:7b-fp16                                     f0643097e171    14 GB     6 weeks ago
        -- starcoder2:3b-q8_0                                     003abcecad23    3.2 GB    6 weeks ago
        -- starcoder2:7b-q8_0                                     d76878e96d8a    7.6 GB    6 weeks ago
        -- model = "starcoder2:7b-q8_0",

        -- codellama:7b-code-q8_0 -- shorter too
        -- codellama:7b-instruct-q8_0 -- longer too
        -- codellama:7b-python-q8_0 -- doesn't do well with FIM (spits out FIM tokens text as if not recognized)... also not sure it supports FIM based on reading docs only code/instruct are mentioned for FIM support)
        -- model = "codellama:7b-code-q8_0",

        -- llama3.1:8b-text-q8_0 -- weird, generated some "code"/text in this file that wasn't terrible!... verbose
        -- llama3.1:8b-instruct-q8_0
        -- model = "llama3.1:8b-instruct-q8_0",
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

    -- defaults to Qwen2.5-Coder (that may work fine with many other models)
    local builder = function()
        error("missing fim prompt builder for " .. body.model)
    end

    -- FYI some models have a bundled (or in ollama Modelfile, IIRC) prompt template that will handle the format, if you set raw=false

    if string.find(body.model, "codellama") then
        builder = function()
            -- TODO:
            return fim.codellama.get_fim_prompt(self)
            -- have it use meta.codellama.sentinel_tokens
            -- FYI if I want a generic builder for all models w/o a specific prompt format then add that, maybe use qwen2.5-coder?
        end

        -- codellama uses <EOT> that seems to not be set as param in modelfile (at least for FIM?)
        --   without this change you will see <EOT> in code at end of completions
        -- ollama show codellama:7b-code-q8_0 --parameters # => no stop param
        -- PRN move stop and other options to model specific config under fim.model.*
        body.options.stop = { "<EOT>" }

        error("review FIM requirements for codellama, make sure you are using expected template, it used to work with qwen like FIM but I changed that to repo level now and would need to test it")

        -- FYI also ollama warns about:
        --    level=WARN source=types.go:512 msg="invalid option provided" option=rope_frequency_base
    elseif string.find(body.model, "Mellum") then
        -- body.options.stop = {
        --     fim.mellum.sentinel_tokens.eos_token,
        --     fim.mellum.sentinel_tokens.file_sep
        -- }
        builder = function()
            return fim.mellum.get_fim_prompt(self)
        end
    elseif string.find(body.model, "starcoder2") then
        -- TODO double check stop is correct by default (completions seem to stop appropirately, so I'm fine with it as is)
        -- body.options.stop = { file_sep? }
        builder = function()
            return fim.starcoder2.get_fim_prompt(self)
        end
    elseif string.find(body.model, "qwen2.5-coder", nil, true) then
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self)
        end
    else
        -- warn that FIM tokens need to be set
        local message = "MISSING FIM SENTINEL TOKENS for this model " .. body.model
        log:error(message)
        error(message)
        return
    end

    log:trace("prefix", "'" .. self.prefix .. "'")
    log:trace("suffix", "'" .. self.suffix .. "'")

    -- ?? for qwen2.5-coder should I use file level context ever? or always repo level?
    -- body.prompt = M.get_file_level_fim_prompt()
    body.prompt = builder()
    log:trace('body.prompt', body.prompt)

    local body_json = vim.json.encode(body)

    log:trace("body", body_json)

    return body_json
end

function OllamaFimBackend:get_current_file_path()
    -- TODO which is better?
    -- local buffer_name = vim.api.nvim_buf_get_name(0)  -- buffer's file path
    return vim.fn.expand('%'):match("([^/]+)$")
end

function OllamaFimBackend:get_repo_name()
    -- TODO confirm repo naming? is it just basename of repo root? or GH link? or org/repo?
    return vim.fn.getcwd():match("([^/]+)$")
end

function OllamaFimBackend.process_sse(data)
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

return OllamaFimBackend
