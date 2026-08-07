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
local gptoss_tokenizer = require("ask-openai.backends.models.gptoss.tokenizer")
local config = require("ask-openai.config")

require("ask-openai.backends.sse.parsers")

---@class FimBackend
---@field ps_chunk PrefixSuffixChunk
---@field rag_matches LSPRankedMatch[]
---@field context CurrentContext
local FimBackend = {}
FimBackend.__index = FimBackend

FimBackend.base_url = ""
---@type CompletionsEndpoints
FimBackend.endpoint = nil

local USE_GPTOSS_RAW = false
function FimBackend.set_fim_model(model)
    -- FYI right now, given I am using llama-server exclusively, toggling is just about changing between the two instances I run at the same time
    --   so, toggling the port/endpoint :)
    FimBackend.base_url = config.get_endpoints()[model].base_url
    if model == models.GPTOSS then
        -- Base URL now derived from configuration (agents subsystem)
        if USE_GPTOSS_RAW then
            -- manually formatted prompt to disable thinking
            -- FYI can also do this with prefill on v1/chat/completions endpoint so this is not necessary to disable thinking
            FimBackend.endpoint = CompletionsEndpoints.llamacpp_completions
        else
            FimBackend.endpoint = CompletionsEndpoints.v1_chat_completions
        end
    elseif model == models.GEMMA4 or model == models.GLM then
        FimBackend.endpoint = CompletionsEndpoints.v1_chat_completions
    else
        FimBackend.endpoint = CompletionsEndpoints.llamacpp_completions -- * preferred for qwen2.5-coder
        -- /completions - raw prompt # https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md#post-completion-given-a-prompt-it-returns-the-predicted-completion
    end
end

---@param ps_chunk PrefixSuffixChunk
---@param rag_matches LSPRankedMatch[]
---@return FimBackend
function FimBackend:new(ps_chunk, rag_matches)
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
        -- model = "", -- not needed in llama-server

        raw = true, -- bypass templates (only /api/generate, not /v1/completions)

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
    FimBackend.set_fim_model(model) -- TODO can we nuke set_fim_model here... and just get the values we need when we need them?
    if string.find(model, "codellama") then
        builder = function()
            return meta.codellama.get_fim_prompt(self)
            -- have it use meta.codellama.sentinel_tokens
        end

        -- codellama uses (codellama.EOT) that seems to not be set as param in modelfile (at least for FIM?)
        --   without this change you will see (codellama.EOT) in code at end of completions
        body.options.stop = { meta.codellama.sentinel_tokens.EOT }

        error("review FIM requirements for codellama, make sure you are using expected template, it used to work with qwen like FIM but I changed that to repo level now and would need to test it")
    elseif string.find(model, "Mellum") then
        -- body.options.stop = {
        --     fim.mellum.sentinel_tokens.EOS_TOKEN,
        --     fim.mellum.sentinel_tokens.FILE_SEP
        -- }
        builder = function()
            return fim.mellum.get_fim_prompt(self)
        end
    elseif string.find(model, "starcoder2") then
        builder = function()
            return fim.starcoder2.get_fim_prompt(self)
        end
    elseif string.find(model, "qwen3coder", nil, true) then
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self)
        end

        body.temperature = 0.7
        body.repeat_penalty = 1.05
        body.top_p = 0.8
        body.top_k = 20
        -- PRN new_qwen3coder_llama_server_legacy_body (or w/e to call it, the old endpoint to do raw FIM prompts)
    elseif string.find(model, "qwen", nil, true) then
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self)
        end
        local level = api.get_fim_reasoning_level()
        if level ~= "off" then
            log:warn("qwen FIM style does not support thinking, OFF is only logical value.. if you setup chat completions style with qwen3 then you can have thinking")
        end
    elseif string.find(model, "bytedance-seed-coder-8b", nil, true) then
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self) -- WORKS FOR repo level using qwen's format entirely! (plus set qwen's stop_tokens to avoid rambles / trailing stop tokens)
            -- return fim.bytedance_seed_coder.get_fim_prompt_file_level_only(self) -- WORKS well for file level using its own SPM format
            -- return fim.bytedance_seed_coder.get_fim_prompt_repo_level(self)
        end
        -- MUST set qwent's tokens as stop tokens too (when using Qwen's repo level fim format)
        body.stop = fim.bytedance_seed_coder.qwen_sentinels.fim_stop_tokens_from_qwen25_coder -- llama-server /completions endpoint uses top-level stop
        body.options.stop = fim.bytedance_seed_coder.qwen_sentinels.fim_stop_tokens_from_qwen25_coder
    elseif model == models.GPTOSS
        or model == models.GEMMA4
        or model == models.GLM
    then
        -- FYI extra logic here is to reuse one template across models when it is the FIM chat completion style I use for gptoss
        --  TODO! strip out glm/gemma4 reuse of gptoss template into own block? would this be less messy?
        --    TODO I should probably rewrite this to not be so hacky given I have special "off" logic for gptoss raw and even in not-raw
        -- FYI I am using my gptoss FIM chat completions FIM style for other chat model FIM setups (not specific to any one of them)
        if USE_GPTOSS_RAW and model == models.GPTOSS then
            -- RAW is gptoss specific
            -- * /completions legacy endpoint:
            builder = function()
                -- * raw prompt /completions, no thinking (I could have model think too, just need to parse that then)
                -- TODO? get rid of raw approach entirely now that prefix is working
                return fim_harmony.gptoss.RETIRED_get_fim_raw_prompt_no_thinking(self)
            end
            body.raw = true
            body.max_tokens = 200 -- FYI if I cut off all thinking
        else
            -- * /v1/chat/completions endpoint (use to have llama-server parse the response, i.e. analsys/thoughts => reasoning_content)
            local level = api.get_fim_reasoning_level()
            body.messages = fim_harmony.gptoss.get_fim_chat_messages(self, level, model)
            body.raw = false -- set here even though was set above
            if model == models.GPTOSS then
                body.chat_template_kwargs = {
                    reasoning_effort = level
                }
            elseif model == models.GLM or model == models.GEMMA4 then
                body.chat_template_kwargs = {
                    -- confirmed works with glm
                    enable_thinking = level ~= "off"
                }
            end

            body.max_tokens = gptoss_tokenizer.get_gptoss_max_tokens_for_level(level)
        end

        -- * common settings
        --   https://github.com/openai/gpt-oss?tab=readme-ov-file#recommended-sampling-parameters
        body.temperature = 1.0
        body.top_p = 1.0
    elseif string.find(model, "codestral", nil, true) then
        builder = function()
            return fim.codestral.get_fim_prompt(self)
        end
    elseif model == models.DEEPSEEK then
        local level = api.get_fim_reasoning_level()
        if level == models.DEEPSEEK_REASONING_EFFORT.PSM then
            builder = function()
                -- FYI WORKING WELL for FILE LEVEL with deepseek_v4_flash_0731
                return fim.deepseek_v4_flash.get_fim_prompt(self)
            end
            -- TODO set endpoint?
            body.raw = true
            -- TODO set max_tokens? deepseek-coder-v2 IIRC had 4k limit on output tokens for FIM prompt... is there a limit on v4 flash too, that would be wise to set to cut off rambling?
            -- only add back stop tokens if needed and then you'll need to look up what they are
            -- body.options.stop = fim.deepseek_v4_flash.sentinel_tokens.FIM_STOP_TOKENS
        else
            -- TODO set endpoint?
            body.messages = fim.deepseek_v4_flash.get_fim_chat_messages(self, level)
            body.raw = false -- set here even though was set above
            body.chat_template_kwargs = {
                -- TODO deep seek level/enable?
                reasoning_effort = level
                enable_thinking = level ~= "off"
            }

            -- ? set max_tokens (what is default, if any?)
            -- body.max_tokens = gptoss_tokenizer.get_gptoss_max_tokens_for_level(level)
            error("TODO not yet implemented, deepseek thinking / chat completions based FIM")
        end
    else
        error("MODEL NOT SUPPORTED '" .. tostring(model) .. "'")
        return
    end

    if builder then
        body.prompt = builder()
        -- log:info(ansi.green_bold('body.prompt:\n'), ansi.green(body.prompt))
    elseif body.messages then
        -- log:info('body.messages', vim.inspect(body.messages))
    else
        error("you must define either the prompt builder OR messages for chat like FIM for: " .. model)
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
