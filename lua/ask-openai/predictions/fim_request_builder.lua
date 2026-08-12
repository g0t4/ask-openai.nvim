local log = require("devtools.logs.logger").universal()
local local_share = require("ask-openai.config.local_share")
local models = require("ask-openai.config.models")
local CurrentContext = require("ask-openai.frontends.context")
local fim = require("ask-openai.backends.models.fim")
local qwen = fim.qwen25coder.sentinel_tokens
local fim_harmony = require("ask-openai.backends.models.gptoss.fim_harmony")
local meta = require("ask-openai.backends.models.meta")
local files = require("ask-openai.helpers.files")
local ansi = require("devtools.ansi")
local api = require("ask-openai.api")
local params = require("ask-openai.agents.models.params")
local gptoss_tokenizer = require("ask-openai.backends.models.gptoss.tokenizer")
local CurlRequest = require("ask-openai.backends.curl_request")
local config = require("ask-openai.config")

require("ask-openai.backends.sse.parsers")

---@class CurlParamsBuilder
---@field body table<string, any>
---@field base_url string
---@field endpoint CompletionsEndpoints
---@field type string
local CurlParamsBuilder = {}
CurlParamsBuilder.__index = CurlParamsBuilder

---@param base_url string
---@param body table<string, any>
---@return CurlParamsBuilder
function CurlParamsBuilder:new(base_url, body)
    local instance = {
        body = body,
        base_url = base_url,
        endpoint = CompletionsEndpoints.llamacpp_completions,
        type = "fim",
    }
    setmetatable(instance, self)
    return instance
end

---@return nil
function CurlParamsBuilder:set_raw_completions()
    self.body.raw = true
    self.endpoint = CompletionsEndpoints.llamacpp_completions
end

---@return nil
function CurlParamsBuilder:set_chat_completions()
    self.body.raw = false
    self.endpoint = CompletionsEndpoints.v1_chat_completions
end

---@return CurlRequestParams
function CurlParamsBuilder:build()
    return {
        body = self.body,
        base_url = self.base_url,
        endpoint = self.endpoint,
        type = self.type,
    }
end

---@class FimRequestBuilder
---@field ps_chunk PrefixSuffixChunk
---@field rag_matches LSPRankedMatch[]
---@field context CurrentContext
local FimRequestBuilder = {}
FimRequestBuilder.__index = FimRequestBuilder

local USE_GPTOSS_RAW = false

---@param ps_chunk PrefixSuffixChunk
---@param rag_matches LSPRankedMatch[]
---@return FimRequestBuilder
function FimRequestBuilder:new(ps_chunk, rag_matches)
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

function FimRequestBuilder:fim_request()
    local max_tokens = 200
    local body = {
        -- FYI keep model notes in MODELS.notes.md
        -- model = "", -- not needed in llama-server
        stream = true,

        -- * MAX tokens (very important)
        max_tokens = max_tokens, -- works for: llama-server /completions, OpenAI's compat endpoints
        -- n_predict = max_tokens, -- llama-server specific (avoid for consistency)


        options = {}, -- empty so I can set stop_tokens below


        logprobs = true,
        post_sampling_probs = true, -- map to 0 to 1.0 (appears to truncate anything that ~0 for probability
        --  whereas if you turn off post_sampling_probs=false => will include very low probability tokens too and not normalize values
        top_logprobs = 5,
        n_cmpl = 1, -- OMFG yes I want a toggle to show them too and let me alt+1 to take first, 2 for second etc!
        -- PRN
        -- TODO! setup n_cmpl -- are these in parallel if fits context size?

        -- PRN
        --  response_fields = ["field1", "field2", ... ] -- limit what is sent back, IIGC this helps with transmission overall and processing on client but it adds overhead to processing on server? or no?
        --  id_slot
        --  samplers (try dry w/ Qwen thinking loops?)
        --    mirostat, xtc - alternative samplers
        --    dry_* dry sampler params (if/when using)
        --  seed
        --
    }

    local model = api.get_fim_model()
    local curl_params = CurlParamsBuilder:new(config.get_endpoints()[model].base_url, body)

    if string.find(model, "codellama") then
        curl_params:set_raw_completions()

        -- codellama uses (codellama.EOT) that seems to not be set as param in modelfile (at least for FIM?)
        --   without this change you will see (codellama.EOT) in code at end of completions
        body.options.stop = { meta.codellama.sentinel_tokens.EOT }
        body.prompt = meta.codellama.get_fim_prompt(self)

        error("review FIM requirements for codellama, make sure you are using expected template, it used to work with qwen like FIM but I changed that to repo level now and would need to test it")
    elseif string.find(model, "Mellum") then
        curl_params:set_raw_completions()
        -- body.options.stop = {
        --     fim.mellum.sentinel_tokens.EOS_TOKEN,
        --     fim.mellum.sentinel_tokens.FILE_SEP
        -- }
        body.prompt = fim.mellum.get_fim_prompt(self)
    elseif string.find(model, "starcoder2") then
        curl_params:set_raw_completions()
        body.prompt = fim.starcoder2.get_fim_prompt(self)
    elseif string.find(model, "qwen3coder", nil, true) then
        curl_params:set_raw_completions()
        body.prompt = fim.qwen25coder.get_fim_prompt(self)

        body.temperature = 0.7
        body.repeat_penalty = 1.05
        body.top_p = 0.8
        body.top_k = 20
    elseif string.find(model, "qwen", nil, true) then
        curl_params:set_raw_completions()
        body.prompt = fim.qwen25coder.get_fim_prompt(self)
        local level = api.get_fim_reasoning_level()
        if level ~= "off" then
            log:warn("qwen FIM style does not support thinking, OFF is only logical value.. if you setup chat completions style with qwen3 then you can have thinking")
        end
    elseif string.find(model, "bytedance-seed-coder-8b", nil, true) then
        curl_params:set_raw_completions()
        body.prompt = fim.qwen25coder.get_fim_prompt(self) -- WORKS FOR repo level using qwen's format entirely! (plus set qwen's stop_tokens to avoid rambles / trailing stop tokens)
        -- body.prompt = fim.bytedance_seed_coder.get_fim_prompt_file_level_only(self) -- WORKS well for file level using its own SPM format
        -- body.prompt = fim.bytedance_seed_coder.get_fim_prompt_repo_level(self)
        -- MUST set qwent's tokens as stop tokens too (when using Qwen's repo level fim format)
        body.stop = fim.bytedance_seed_coder.qwen_sentinels.fim_stop_tokens_from_qwen25_coder -- llama-server /completions endpoint uses top-level stop
        body.options.stop = fim.bytedance_seed_coder.qwen_sentinels.fim_stop_tokens_from_qwen25_coder
    elseif model == models.GPTOSS
        or model == models.GEMMA4
        or model == models.GLM
        or model == models.MUSE
        or model == models.NEMO
    then
        if USE_GPTOSS_RAW and model == models.GPTOSS then
            curl_params:set_raw_completions()
            -- ? get rid of raw approach entirely now that prefix is working
            body.prompt = fim_harmony.gptoss.RETIRED_get_fim_raw_prompt_no_thinking(self)
            body.raw = true
            body.max_tokens = 2000 -- FYI if I cut off all thinking
        else
            curl_params:set_chat_completions()
            local level = api.get_fim_reasoning_level()
            body.messages = fim_harmony.gptoss.get_fim_chat_messages(self, level, model)
            body.raw = false
            if model == models.GPTOSS then
                body.chat_template_kwargs = {
                    reasoning_effort = level
                }
            elseif model == models.GLM
                or model == models.GEMMA4
                or model == models.NEMO then
                -- enable_thinking confirmed works with glm and nemo-lightning
                --   (nemo-lightning's chat template has no effort/strength level kwarg)
                body.chat_template_kwargs = {
                    enable_thinking = level ~= "off"
                }
                -- TODO other models use their overrides in params.
            elseif model == models.MUSE then
                body = params.body_for_muse_glimmer(body, level)
            end

            body.max_tokens = gptoss_tokenizer.get_gptoss_max_tokens_for_level(level)
        end

        -- * common settings
        --   https://github.com/openai/gpt-oss?tab=readme-ov-file#recommended-sampling-parameters
        body.temperature = 1.0
        body.top_p = 1.0
    elseif string.find(model, "codestral", nil, true) then
        curl_params:set_raw_completions()
        body.prompt = fim.codestral.get_fim_prompt(self)
    elseif model == models.DEEPSEEK then
        curl_params.body.max_tokens = nil -- clear default 200 max tokens
        local level = api.get_fim_reasoning_level()
        if level == models.DEEPSEEK_REASONING_EFFORT.PSM then
            -- FYI WORKING WELL for FILE LEVEL with deepseek_v4_flash_0731
            body.prompt = fim.deepseek_v4_flash.get_fim_prompt(self)
            curl_params:set_raw_completions()
            -- TODO set max_tokens? deepseek-coder-v2 IIRC had 4k limit on output tokens for FIM prompt... is there a limit on v4 flash too, that would be wise to set to cut off rambling?
            -- only add back stop tokens if needed and then you'll need to look up what they are
            -- body.options.stop = fim.deepseek_v4_flash.sentinel_tokens.FIM_STOP_TOKENS
        else
            -- TODO set explicit max tokens?
            body.messages = fim.deepseek_v4_flash.get_fim_chat_messages(self, level)
            curl_params:set_chat_completions()
            -- apply deepseek recommended sampling + reasoning kwargs (mirrors agents/rewrite frontend)
            --   handles: temperature/top_p/max_tokens + chat_template_kwargs for enable_thinking & reasoning_effort
            body = params.body_for_deepseek4flash(body, level)
            curl_params.body = body
        end
    else
        error("MODEL NOT SUPPORTED '" .. tostring(model) .. "'")
    end

    if not body.prompt and not body.messages then
        error("you must define either the prompt OR messages for chat like FIM for: " .. model)
    end

    return CurlRequest:new(curl_params:build())
end

function FimRequestBuilder.inject_file_path_test_seam()
    return files.get_current_file_relative_path()
end

function FimRequestBuilder:get_repo_name()
    -- TODO confirm repo naming? is it just basename of repo root? or GH link? or org/repo?
    return vim.fn.getcwd():match("([^/]+)$")
end

return FimRequestBuilder
