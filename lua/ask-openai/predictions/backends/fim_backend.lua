local log = require("ask-openai.logs.logger").predictions()
local CurrentContext = require("ask-openai.predictions.context")
local fim = require("ask-openai.backends.models.fim")
local meta = require("ask-openai.backends.models.meta")
local files = require("ask-openai.helpers.files")
local ansi = require("ask-openai.predictions.ansi")
local local_share = require("ask-openai.config.local_share")
local api = require("ask-openai.api")

require("ask-openai.backends.sse")

---@class FimBackend
---@field ps_chunk PrefixSuffixChunk
---@field rag_matches LSPRankedMatch[]
---@field context CurrentContext
local FimBackend = {}
FimBackend.__index = FimBackend

local use_model = ""
local url = ""
local use_gptoss_raw = false
FimBackend.endpoint_ollama_api_generate = false
FimBackend.endpoint_ollama_api_chat = false
FimBackend.endpoint_llama_server_proprietary_completions = false
FimBackend.endpoint_openaicompat_chat_completions = false
function FimBackend.set_fim_model(model)
    -- FYI right now, given I am using llama-server exclusively, toggling is just about changing between the two instances I run at the same time
    --   so, toggling the port/endpoint :)
    if model == "gptoss" then
        use_model = "gpt-oss:120b"
        if use_gptoss_raw then
            url = "http://ollama:8013/completions" -- manually formatted prompt to disable thinking
        else
            url = "http://ollama:8013/v1/chat/completions"
        end
    else
        use_model = "qwen25coder"
        url = "http://ollama:8012/completions" -- * preferred for qwen2.5-coder
        -- /completions - raw prompt # https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md#post-completion-given-a-prompt-it-returns-the-predicted-completion
    end
    -- add new options in config so I no longer have to switch in code;
    -- use_model = "bytedance-seed-coder-8b"
    -- use_model = "qwen3-coder:30b-a3b-q8_0" -- just call this qwen3coder

    -- * ollama
    -- url = "http://ollama:11434/api/generate" -- raw prompt: qwen2.5-coder(ollama)
    -- url = "http://ollama:11434/api/chat" -- gpt-oss(ollama works)
    -- url = "http://ollama:11434/v1/chat/completions" -- gpt-oss(ollama works)

    -- * parser toggles
    --   (make based on url/model so not have to explicitly config too)
    FimBackend.endpoint_ollama_api_generate = string.match(url, "/api/generate$")
    FimBackend.endpoint_ollama_api_chat = string.match(url, "/api/chat$")
    FimBackend.endpoint_llama_server_proprietary_completions = string.match(url, ":801%d/completions$")
    FimBackend.endpoint_openaicompat_chat_completions = string.match(url, "v1/chat/completions$")
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
    -- log:trace("context: ", vim.inspect(instance.context))
    return instance
end

function FimBackend:body_for()
    local max_tokens = 200
    local body = {
        -- FYI! keep model notes in MODELS.notes.md
        -- for llama-server this is only to select the right prompt/chat builder below
        model = use_model,

        raw = true, -- bypass templates (only /api/generate, not /v1/completions)

        stream = true,

        -- * MAX tokens (very important)
        max_tokens = max_tokens, -- works for: llama-server /completions, OpenAI's compat endpoints
        -- n_predict = max_tokens, -- llama-server specific (avoid for consistency)
        -- options.num_predict = max_tokens, -- ollama's /api/generate

        -- * llama-server /completions endpoint
        response_fields = {
            -- set fields so the rest are skipped, else the SSEs are HUGE, and last has entire prompt too
            "content", "timings", "truncated", "stop_type", "stopping_word",
            "generation_settings", -- for last SSE to reflect inputs
        },
        -- these seem to be included regardless: "index","content","tokens","stop","id_slot","tokens_predicted","tokens_evaluated"
        --
        -- timings_per_token = false, -- default false, shows timings on every SSE, BTW doesn't seem to control tokens_predicted, tokens_evaluated per SSE

        -- TODO temperature, top_p,
        options = {} -- empty so I can set stop_tokens below (IIRC for ollama only?)
    }

    -- FYI some models have a bundled (or in ollama Modelfile, IIRC) prompt template that will handle the format, if you set raw=false

    if string.find(body.model, "codellama") then
        builder = function()
            return fim.codellama.get_fim_prompt(self)
            -- have it use meta.codellama.sentinel_tokens
        end

        -- -- codellama template:
        -- --    {{- if .Suffix }}<PRE> {{ .Prompt }} <SUF>{{ .Suffix }} <MID>
        -- sentinel_tokens = {
        --     fim_prefix = "<PRE> ",
        --     fim_suffix = " <SUF>",
        --     fim_middle = " <MID>",
        -- }

        -- codellama uses <EOT> that seems to not be set as param in modelfile (at least for FIM?)
        --   without this change you will see <EOT> in code at end of completions
        -- ollama show codellama:7b-code-q8_0 --parameters # => no stop param
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
    elseif string.find(body.model, "qwen3coder", nil, true) then
        -- TODO verify this is compatible with Qwen2.5-Coder FIM tokens, I believe it is
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self)
        end

        body.temperature = 0.7
        body.repeat_penalty = 1.05
        body.top_p = 0.8
        body.top_k = 20
        -- PRN new_qwen3coder_llama_server_legacy_body (or w/e to call it, the old endpoint to do raw FIM prompts)

        -- TODO! stop token isn't set! should I just remove this... I have them commented out in the other file linked here:
        body.options.stop = fim.qwen25coder.sentinel_tokens.fim_stop_tokens
    elseif string.find(body.model, "qwen25coder", nil, true) then
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self)
        end
        -- TODO! stop token isn't set! should I just remove this... I have them commented out in the other file linked here:
        body.options.stop = fim.qwen25coder.sentinel_tokens.fim_stop_tokens
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
        if not use_gptoss_raw then
            -- * /v1/chat/completions endpoint (use to have llama-server parse the response, i.e. analsys/thoughts => reasoning_content)
            body.messages = fim.gptoss.get_fim_chat_messages(self)
            body.raw = false -- not used in chat -- FYI hacky
            local level = api.get_reasoning_level()
            body.chat_template_kwargs = {
                reasoning_effort = level
            }
            if level == "high" then
                body.max_tokens = 8192 -- high thinking
            elseif level == "medium" then
                body.max_tokens = 4096 -- medium thinking
            else
                body.max_tokens = 2048 -- low thinking
            end
        else
            -- * /completions legacy endpoint:
            builder = function()
                -- * raw prompt /completions, no thinking (I could have model think too, just need to parse that then)
                return fim.gptoss.get_fim_raw_prompt_no_thinking(self)
            end
            body.max_tokens = 200 -- FYI if I cut off all thinking
            -- body.max_tokens = 2048 -- low thinking (if/when I allow thinking and use my harmoney_parser)
        end

        -- body.options.stop = fim.gptoss.sentinel_tokens.fim_stop_tokens -- TODO?
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

    if builder then
        body.prompt = builder()
        -- log:info(ansi.green_bold('body.prompt:\n'), ansi.green(body.prompt))
    elseif body.messages then
        local _, log_threshold = local_share.get_log_threshold()
        -- TODO if verbose then log all messages
        -- log:info('body.messages', vim.inspect(body.messages))
        if log_threshold < local_share.LOG_LEVEL_NUMBERS.WARN then
            -- IOTW INFO LOGGING (and below)
            -- HACK: ONLY log last message, around cursor_marker
            -- FYI WON'T WORK WITH non-gptoss models b/c they have different cursor_marker
            -- TODO just pass along the original lines instead of doing it this way? (splitting)?
            local last_message = body.messages[#body.messages]
            local cursor_marker = '<|fim_middle|>'
            local lines = vim.split(last_message.content, '\n', true)
            local cursor_index = nil
            local cursor_count = 0
            for i, line in ipairs(lines) do
                if line:find(cursor_marker, 1, true) then
                    cursor_index = i
                    cursor_count = cursor_count + 1
                    if cursor_count == 2 then
                        break
                    end
                end
            end
            if cursor_index then
                local start_idx = math.max(1, cursor_index - 5)
                local end_idx = math.min(#lines, cursor_index + 5)
                local snippet = table.concat(vim.list_slice(lines, start_idx, end_idx), '\n')
                log:info(ansi.red_bold('CURSOR CONTEXT:\n'), ansi.red(snippet))
            else
                log:info(ansi.yellow('No <|fim_middle|> marker found, you messed up big time!'))
            end
        end
    else
        error("you must define either the prompt builder OR messages for chat like FIM for: " .. body.model)
    end

    -- FYI hack to send back unencoded body and addidng url here is for PoC on PREDIDCTIONS FRONTEND
    return body, url
end

function FimBackend.inject_file_path_test_seam()
    return files.get_current_file_relative_path()
end

function FimBackend:get_repo_name()
    -- TODO confirm repo naming? is it just basename of repo root? or GH link? or org/repo?
    return vim.fn.getcwd():match("([^/]+)$")
end

return FimBackend
