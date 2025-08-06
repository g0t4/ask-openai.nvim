local log = require("ask-openai.logs.logger").predictions()
local CurrentContext = require("ask-openai.prediction.context")
local fim = require("ask-openai.backends.models.fim")
local meta = require("ask-openai.backends.models.meta")
local files = require("ask-openai.helpers.files")


-- * primary models I am testing (keep notes in MODELS.notes.md)
local use_model = "qwen2.5-coder:7b-instruct-q8_0"
-- local use_model = "gpt-oss:20b"
-- local use_model = "qwen3-coder:30b-a3b-q8_0"
--
-- * llama-server (llama-cpp)
local url = "http://ollama:8012/completions" -- raw prompt: qwen2.5-coder(llama-server)
-- local url = "http://ollama:8012/chat/completions" -- gpt-oss(llama-server, not working yet)
-- * ollama
-- local url = "http://ollama:11434/api/generate" -- raw prompt: qwen2.5-coder(ollama)
-- local url = "http://ollama:11434/api/chat" -- gpt-oss(ollama works)
-- local url = "http://ollama:11434/v1/chat/completions" -- gpt-oss(ollama works)
--
-- * parser toggles
--   (make based on url/model so not have to explicitly config too)
local endpoint_ollama_api_generate = string.match(url, "/api/generate$")
local endpoint_ollama_api_chat = string.match(url, "/api/chat$")
local endpoint_llama_server_proprietary_completions = string.match(url, ":8012/completions$")
local endpoint_openaicompat_chat_completions = string.match(url, "v1/chat/completions$")

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
        -- FYI! keep model notes in MODELS.notes.md
        -- for llama-server this is only to select the right prompt/chat builder below
        model = use_model,

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
    elseif string.find(body.model, "qwen3-coder", nil, true) then
        -- TODO! verify this is compatible with Qwen2.5-Coder FIM tokens, I believe it is
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self)
        end
        -- TODO! stop token isn't set! should I just remove this... I have them commented out in the other file linked here:
        body.options.stop = fim.qwen25coder.sentinel_tokens.fim_stop_tokens
        log:error("stop token: " .. vim.inspect(body.options.stop))
    elseif string.find(body.model, "qwen2.5-coder", nil, true) then
        builder = function()
            return fim.qwen25coder.get_fim_prompt(self)
        end
        -- TODO! stop token isn't set! should I just remove this... I have them commented out in the other file linked here:
        body.options.stop = fim.qwen25coder.sentinel_tokens.fim_stop_tokens
        log:error("stop token: " .. vim.inspect(body.options.stop))
    elseif string.find(body.model, "gpt-oss", nil, true) then
        body.messages = fim.gpt_oss.get_fim_chat_messages(self)
        body.raw = false -- not used in chat -- FYI hacky
        -- body.options.stop = fim.gpt_oss.sentinel_tokens.fim_stop_tokens
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
    elseif body.messages == nil then
        error("you must define either the prompt builder OR messages for chat like FIM for: " .. body.model)
    end
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
            -- vim.print(parsed)
            local parsed_chunk
            if endpoint_llama_server_proprietary_completions then
                parsed_chunk, done, done_reason = parse_llama_cpp_server(parsed)
            elseif endpoint_openaicompat_chat_completions then
                parsed_chunk, done, done_reason, thinking = parse_sse_oai_chat_completions(parsed)
            elseif endpoint_ollama_api_chat then
                parsed_chunk, done, done_reason = parse_sse_ollama_chat(parsed)
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

function parse_sse_oai_chat_completions(sse)
    content = ""
    if sse.choices and sse.choices[1] then
        content = sse.choices[1].delta.content
        if content == vim.NIL then
            -- TODO fix llama-server + gpt-oss on chat/completions
            --   streaming response streams low level tokens including channel!
            --   and the first response's content is vim.NIL (seems to indicate the template issue too)
            error("content: " .. tostring(content) .. " is vim.NIL, WHY?!")
            content = ""
        end
        reasoning = sse.choices[1].delta.reasoning
        -- TODO SHOW THINKING!!!?
    end
    done = sse.finish_reason ~= nil -- or "null"? or vim.NIL
    finish_reason = sse.finish_reason
    return content, done, finish_reason, reasoning

    -- * gpt-oss:20b chat/completions ollama example:
    -- reasoning/thinking content (full message, all fields):
    --   {"id":"chatcmpl-900","object":"chat.completion.chunk","created":1754453131,"model":"gpt-oss:20b","system_fingerprint":"fp_ollama",
    --     "choices":[{"index":0,"delta":{"role":"assistant","content":"","reasoning":"?"},"finish_reason":null}]}
    -- content:
    --   "choices":[{"index":0,"delta":{"role":"assistant","content":" }"},"finish_reason":null}]}
    --   "choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"stop"}]}
end

function parse_sse_ollama_chat(sse)
    -- vim.print(sse)
    --   created_at = "2025-08-06T03:41:18.754207861Z",
    --   done = true,
    --   done_reason = "load",
    --   message = {
    --     content = "",
    --     role = "assistant"
    --   },

    -- it has "thinking"!
    -- gpt-oss:
    --   "message":{"role":"assistant","content":"","thinking":"   "},"done":false}

    message = ""
    if sse.message then
        message = sse.message.content
    end
    return message, sse.done, sse.done_reason
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
