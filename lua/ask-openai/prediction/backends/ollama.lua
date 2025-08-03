local log = require("ask-openai.logs.logger").predictions()
local log = require("ask-openai.logs.logger").predictions()
local CurrentContext = require("ask-openai.prediction.context")
local fim = require("ask-openai.backends.models.fim")
local meta = require("ask-openai.backends.models.meta")
local files = require("ask-openai.helpers.files")

local use_llama_cpp_server = true


---@class OllamaFimBackend
---@field prefix string
---@field suffix string
---@field context CurrentContext
local OllamaFimBackend = {}
OllamaFimBackend.__index = OllamaFimBackend

---@param prefix string
---@param suffix string
---@param rag_matches table
---@return OllamaFimBackend
function OllamaFimBackend:new(prefix, suffix, rag_matches)
    local always_include = {
        yanks = true,
        matching_ctags = true,
        project = true,
    }
    local instance = {
        prefix = prefix,
        suffix = suffix,
        rag_matches = rag_matches,
        -- FYI gonna limit FIM while I test different sources
        context = CurrentContext:items("", always_include)
    }
    setmetatable(instance, self)
    log:info("context: ", vim.inspect(instance.context))
    return instance
end

function OllamaFimBackend:request_options()
    local url = "http://ollama:11434/api/generate" -- ollama serve
    if use_llama_cpp_server then
        url = "http://ollama:8012/completions" -- llama-server
    end
    local options = {
        command = "curl",
        args = {
            "--fail-with-body",
            "-sSL",
            "--no-buffer", -- test w/ `curl *` vs `curl * | cat`
            "-X", "POST",
            url,
            "-H", "Content-Type: application/json",
            "-d", self:body_for(),
        },
    }
    return options
end

function OllamaFimBackend:body_for()
    local body = {

        -- https://huggingface.co/collections/JetBrains/mellum-68120b4ae1423c86a2da007a
        -- model = "huggingface.co/JetBrains/Mellum-4b-base-gguf", -- no language specific fine tuning
        -- model = "huggingface.co/JetBrains/Mellum-4b-sft-python-gguf", -- ** did better with Lua than base!
        -- kotlin exists but no gguf on hf yet:
        --   https://huggingface.co/JetBrains/Mellum-4b-sft-kotlin
        -- TODO add in other fine tunes for languages as released

        -- FYI set of possible models for demoing impact of fine tune
        -- qwen2.5-coder:7b-base-q8_0  -- ** shorter responses, more "EOF" focused
        -- qwen2.5-coder:14b-base-q8_0 -- ** shorter responses, more "EOF" focused
        -- qwen2.5-coder:7b-instruct-q8_0 -- DO NOT USE instruct
        -- model = "qwen2.5-coder:7b-base-q8_0", -- ** favorite
        --
        -- model is NOT ACTUALLY USED when hosting llama-server
        -- model = "huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M",
        model = "qwen3-coder:30b-a3b-fp16",
        -- # TODO optimal params? any new updates for llama-server that would help?
        -- llama-server -hf unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M --host 0.0.0.0 --port 8012 --batch-size 2048 --ubatch-size 2048 --flash-attn --n-gpu-layers 99
        -- TODO params.n_ctx = 0;
        -- REMEMBER just host the model in llama-server, it only runs one

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

        -- model = "codestral:22b-v0.1-q4_K_M",

        -- ** FAST MoE
        -- model = "deepseek-coder-v2:16b-lite-base-q8_0", -- *** 217 TPS! WORKS GOOD!
        -- model = "deepseek-coder-v2:16b-lite-base-fp16", -- FITS! and its still fast (MoE)


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
    elseif string.find(body.model, "Qwen3-Coder", nil, true) then
        -- TODO! verify this is compatible with Qwen2.5-Coder FIM tokens, I believe it is
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self)
        end
        body.options.stop = fim.qwen25coder.sentinel_tokens.fim_stop_tokens
    elseif string.find(body.model, "qwen2.5-coder", nil, true) then
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self)
        end
        body.options.stop = fim.qwen25coder.sentinel_tokens.fim_stop_tokens
    elseif string.find(body.model, "codestral", nil, true) then
        builder = function()
            return fim.codestral.get_fim_prompt(self)
        end
        -- TODO? DROP temperature per:
        --   https://github.com/ollama/ollama/issues/4709
        --   make it more repeatable?
        -- body.options.temperature = 0.0

        -- TODO! investigate temp (etc) for all models

        -- TODO set stop token to EOS? IIAC this is already set?!
        -- body.options.stop = { fim.codestral.sentinel_tokens.eos_token }
    elseif string.find(body.model, "deepseek-coder-v2", nil, true) then
        builder = function()
            return fim.deepseek_coder_v2.get_fim_prompt(self)
        end

        body.options.stop = fim.deepseek_coder_v2.sentinel_tokens.fim_stop_tokens
    else
        -- warn that FIM tokens need to be set
        local message = "MISSING FIM SENTINEL TOKENS for this model " .. body.model
        log:error(message)
        error(message)
        return
    end

    -- ?? for qwen2.5-coder should I use file level context ever? or always repo level?
    -- body.prompt = M.get_file_level_fim_prompt()
    body.prompt = builder()
    log:trace('body.prompt', body.prompt)

    return vim.json.encode(body)
end

function OllamaFimBackend:inject_file_path_test_seam()
    return files.get_current_file_relative_path()
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

        if success and parsed then
            if use_llama_cpp_server then
                parsed_chunk, done, done_reason = parse_llama_cpp_server(parsed)
            else
                parsed_chunk, done, done_reason = parse_ollama_api_generate(parsed)
            end
            chunk = (chunk or "") .. parsed_chunk
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    -- TODO test passing back finish_reason (i.e. for an empty prediction log entry)
    return chunk, done, done_reason
end

function parse_llama_cpp_server(sse)
    -- {"index":0,"content":"\",","tokens":[497],"stop":false,"id_slot":-1,"tokens_predicted":14,"tokens_evaluated":1963}
    -- stop: true => a few fields (it returns entire prompt too so it's huge!... maybe skip logging the prompt field?)
    -- "truncated": false,
    -- "stop_type": "eos",
    -- "stopping_word": "",
    return sse.content, sse.content, sse.stop_type
end

function parse_ollama_api_generate(sse)
    -- *** examples /api/generate:
    --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.1915236Z","response":"\n","done":false}
    --  done example:
    --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.2800621Z","response":"","done":true,"done_reason":"stop","total_duration":131193100,"load_duration":16550700,"prompt_eval_count":19,"prompt_eval_duration":5000000,"eval_count":12,"eval_duration":106000000}

    return sse.response, sse.done, sse.done_reason
end

return OllamaFimBackend
