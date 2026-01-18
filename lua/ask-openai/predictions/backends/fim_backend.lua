local log = require("ask-openai.logs.logger").predictions()
local CurrentContext = require("ask-openai.predictions.context")
local fim = require("ask-openai.backends.models.fim")
local qwen = fim.qwen25coder.sentinel_tokens
local harmony_fim = require("ask-openai.backends.models.fim_harmony")
local meta = require("ask-openai.backends.models.meta")
local files = require("ask-openai.helpers.files")
local ansi = require("ask-openai.predictions.ansi")
local api = require("ask-openai.api")
local gptoss_tokenizer = require("ask-openai.backends.models.gptoss.tokenizer")

require("ask-openai.backends.sse.parsers")

---@class FimBackend
---@field ps_chunk PrefixSuffixChunk
---@field rag_matches LSPRankedMatch[]
---@field context CurrentContext
local FimBackend = {}
FimBackend.__index = FimBackend

local use_model = ""

FimBackend.base_url = ""
---@type CompletionsEndpoints
FimBackend.endpoint = nil

local use_gptoss_raw = true
function FimBackend.set_fim_model(model)
    -- FYI right now, given I am using llama-server exclusively, toggling is just about changing between the two instances I run at the same time
    --   so, toggling the port/endpoint :)
    if model == "gptoss" then
        use_model = "gpt-oss:120b"
        FimBackend.base_url = "http://build21.lan:8013"
        if use_gptoss_raw then
            -- manually formatted prompt to disable thinking
            FimBackend.endpoint = CompletionsEndpoints.llamacpp_completions
        else
            FimBackend.endpoint = CompletionsEndpoints.oai_v1_chat_completions
        end
    else
        use_model = "qwen25coder"
        FimBackend.base_url = "http://build21.lan:8012"
        FimBackend.endpoint = CompletionsEndpoints.llamacpp_completions -- * preferred for qwen2.5-coder
        -- /completions - raw prompt # https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md#post-completion-given-a-prompt-it-returns-the-predicted-completion
    end
    -- add new options in config so I no longer have to switch in code;
    -- use_model = "bytedance-seed-coder-8b"
    -- use_model = "qwen3-coder:30b-a3b-q8_0" -- just call this qwen3coder

    -- * ollama
    -- FimBackend.url = "http://ollama:11434"
    -- FimBackend.endpoint = CompletionsEndpoints.ollama_api_generate -- raw prompt: qwen2.5-coder(ollama)
    -- FimBackend.endpoint = CompletionsEndpoints.ollama_api_chat -- gpt-oss(ollama works)
    -- FimBackend.endpoint = CompletionsEndpoints.oai_v1_chat_completions -- gpt-oss(ollama works)
end

FimBackend.set_fim_model("qwen25coder") -- default

---@param ps_chunk PrefixSuffixChunk
---@param rag_matches LSPRankedMatch[]
---@return FimBackend
function FimBackend:new(ps_chunk, rag_matches, model)
    FimBackend.set_fim_model(model)
    local always_include = {
        yanks = true,
        matching_ctags = true, -- TODO should RAG replace this by default? and just have more RAG matches (FYI RAG can index the ctags file too)
        project = true,
    }
    local instance = {
        ps_chunk = ps_chunk,
        rag_matches = rag_matches,
        -- FYI gonna limit FIM while I test different sources
        context = CurrentContext:items("", always_include)
    }
    setmetatable(instance, self)
    return instance
end

function FimBackend:body_for()
    local max_tokens = 200
    local body = {
        -- FYI keep model notes in MODELS.notes.md
        model = use_model,

        raw = true, -- bypass templates (only /api/generate, not /v1/completions)

        stream = true,

        -- * MAX tokens (very important)
        max_tokens = max_tokens, -- works for: llama-server /completions, OpenAI's compat endpoints
        -- n_predict = max_tokens, -- llama-server specific (avoid for consistency)
        -- options.num_predict = max_tokens, -- ollama's /api/generate

        options = {} -- empty so I can set stop_tokens below (IIRC for ollama only?)
    }

    if string.find(body.model, "codellama") then
        builder = function()
            return meta.codellama.get_fim_prompt(self)
            -- have it use meta.codellama.sentinel_tokens
        end

        -- codellama uses (codellama.EOT) that seems to not be set as param in modelfile (at least for FIM?)
        --   without this change you will see (codellama.EOT) in code at end of completions
        -- ollama show codellama:7b-code-q8_0 --parameters # => no stop param
        body.options.stop = { meta.codellama.sentinel_tokens.EOT }

        error("review FIM requirements for codellama, make sure you are using expected template, it used to work with qwen like FIM but I changed that to repo level now and would need to test it")
        -- also ollama warns about:
        --    level=WARN source=types.go:512 msg="invalid option provided" option=rope_frequency_base
    elseif string.find(body.model, "Mellum") then
        -- body.options.stop = {
        --     fim.mellum.sentinel_tokens.EOS_TOKEN,
        --     fim.mellum.sentinel_tokens.FILE_SEP
        -- }
        builder = function()
            return fim.mellum.get_fim_prompt(self)
        end
    elseif string.find(body.model, "starcoder2") then
        builder = function()
            return fim.starcoder2.get_fim_prompt(self)
        end
    elseif string.find(body.model, "qwen3coder", nil, true) then
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self)
        end

        body.temperature = 0.7
        body.repeat_penalty = 1.05
        body.top_p = 0.8
        body.top_k = 20
        -- PRN new_qwen3coder_llama_server_legacy_body (or w/e to call it, the old endpoint to do raw FIM prompts)
    elseif string.find(body.model, "qwen25coder", nil, true) then
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self)
        end
    elseif string.find(body.model, "bytedance-seed-coder-8b", nil, true) then
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self) -- WORKS FOR repo level using qwen's format entirely! (plus set qwen's stop_tokens to avoid rambles / trailing stop tokens)
            -- return fim.bytedance_seed_coder.get_fim_prompt_file_level_only(self) -- WORKS well for file level using its own SPM format
            -- return fim.bytedance_seed_coder.get_fim_prompt_repo_level(self)
        end
        -- MUST set qwent's tokens as stop tokens too (when using Qwen's repo level fim format)
        body.stop = fim.bytedance_seed_coder.qwen_sentinels.fim_stop_tokens_from_qwen25_coder -- llama-server /completions endpoint uses top-level stop
        body.options.stop = fim.bytedance_seed_coder.qwen_sentinels.fim_stop_tokens_from_qwen25_coder
    elseif string.find(body.model, "gpt-oss", nil, true) then
        if use_gptoss_raw then
            -- * /completions legacy endpoint:
            builder = function()
                -- * raw prompt /completions, no thinking (I could have model think too, just need to parse that then)
                -- TODO? get rid of raw approach entirely now that prefix is working
                return harmony_fim.gptoss.RETIRED_get_fim_raw_prompt_no_thinking(self)
            end
            body.raw = true
            body.max_tokens = 200 -- FYI if I cut off all thinking
        else
            -- * /v1/chat/completions endpoint (use to have llama-server parse the response, i.e. analsys/thoughts => reasoning_content)
            local level = api.get_fim_reasoning_level()
            body.messages = harmony_fim.gptoss.get_fim_chat_messages(self, level)
            body.raw = false -- set here even though was set above
            body.chat_template_kwargs = {
                reasoning_effort = level
            }

            body.max_tokens = gptoss_tokenizer.get_gptoss_max_tokens_for_level(level)
        end

        -- * common settings
        --   https://github.com/openai/gpt-oss?tab=readme-ov-file#recommended-sampling-parameters
        body.temperature = 1.0
        body.top_p = 1.0
    elseif string.find(body.model, "codestral", nil, true) then
        builder = function()
            return fim.codestral.get_fim_prompt(self)
        end
        -- TODO? DROP temperature per:
        --   https://github.com/ollama/ollama/issues/4709
        --   make it more repeatable?
        -- body.options.temperature = 0.0
        -- body.options.stop = { fim.codestral.sentinel_tokens.EOS_TOKEN }
    elseif string.find(body.model, "deepseek-coder-v2", nil, true) then
        builder = function()
            return fim.deepseek_coder_v2.get_fim_prompt(self)
        end

        body.options.stop = fim.deepseek_coder_v2.sentinel_tokens.fim_stop_tokens
    else
        error("MODEL NOT SUPPORTED")
        return
    end

    if builder then
        body.prompt = builder()
        -- log:info(ansi.green_bold('body.prompt:\n'), ansi.green(body.prompt))
    elseif body.messages then
        -- log:info('body.messages', vim.inspect(body.messages))
    else
        error("you must define either the prompt builder OR messages for chat like FIM for: " .. body.model)
    end

    return body
end

function FimBackend.inject_file_path_test_seam()
    return files.get_current_file_relative_path()
end

function FimBackend:get_repo_name()
    -- TODO confirm repo naming? is it just basename of repo root? or GH link? or org/repo?
    return vim.fn.getcwd():match("([^/]+)$")
end

return FimBackend
