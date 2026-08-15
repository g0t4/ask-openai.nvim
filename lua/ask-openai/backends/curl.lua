local log = require("devtools.logs.logger").universal()
local completion_logger = require("ask-openai.logs.completion_logger")
local CurlRequest = require("ask-openai.backends.curl_request")
local SSEDataOnlyParser = require("ask-openai.backends.sse.data_only_parser")
local safely = require("ask-openai.helpers.safely")
local json = require('dkjson')
local uv_spawn = require("ask-openai.helpers.uv_spawn").uv_spawn

local Curl = {}

---@enum CompletionsEndpoints
_G.CompletionsEndpoints = {
    -- llama-server non-openai:
    llamacpp_completions = "/completions",

    -- openai compat (but I've been developing this for llama-server for so long I can't guarantee that without testing)
    v1_chat_completions = "/v1/chat/completions",
}

---@alias OnParsedSSE fun(sse_parsed: LlamaServerSSEBase)
---@alias ExplainError fun(text: string)
---@alias OnCurlExitedSuccessfully fun()

---@class LlamaServerTimings
---@field draft_n_accepted integer
---@field draft_n integer
---@field cache_n integer
---@field predicted_n integer
---@field prompt_per_second number
---@field prompt_ms number
---@field prompt_per_token_ms number
---@field predicted_ms number
---@field predicted_per_token_ms number
---@field prompt_n integer
---@field predicted_per_second number

---@class LlamaServerGenerationSettings
---@field generation_prompt? string
---@field max_tokens integer -- -1 == no limit
---@field temperature number

---@class LlamaServerVerbose
---@field content? string
---@field generation_settings LlamaServerGenerationSettings
---@field model string
---@field prompt string
---@field stop boolean
---@field stop_type string -- i.e. "eos"
---@field stopping_word string
---@field timings LlamaServerTimings -- PREFER to use sse.timings
---@field truncated boolean

---@class LlamaServerSSEBase
---@field timings LlamaServerTimings
---@field model string

---@class LlamaServerChatCompletionSSE_Delta
---@field role? string -- IIRC set on first SSE
---@field content? string|vim.NIL
---@field reasoning_content? string|vim.NIL
---@field index? integer
---@field __verbose? LlamaServerVerbose -- only chat completions has __verbose in my current testing

---@class LlamaServerLogProbs_Content_Prob
---@field bytes integer[]
---@field id integer
---@field prob number -- when post_sampling_probs=true (0 to 1)
---@field logprob number -- when post_sampling_probs=false (FYI only one of prob/logprob is returned)
---@field token string

---@class LlamaServerLogProbs_Content : LlamaServerLogProbs_Content_Prob
---field top_probs? LlamaServerLogProbs_Content_Prob[]

---@class LlamaServerLogProbs
---@field content? LlamaServerLogProbs_Content[]

---@class LlamaServerChatCompletionSSE_Choice
---@field delta LlamaServerChatCompletionSSE_Delta
---@field finish_reason string|vim.NIL
---@field index? integer
---@field logprobs? LlamaServerLogProbs

-- [INFO ]  sse {
--   choices = { {
--       delta = {
--         content = " error"
--       },
--       finish_reason = vim.NIL,
--       index = 0
--     } },
--   created = 1786650360,
--   id = "chatcmpl-hdvDM7I5IfMsstQoI6oSXS2qyGrEwJHQ",
--   model = "meta-models/Muse-Glimmer-30B-GGUF:Q4_K_XL",
--   object = "chat.completion.chunk",
--   system_fingerprint = "b10413-f65e568fd"
-- }
---@class LlamaServerChatCompletionSSE : LlamaServerSSEBase
---@field choices LlamaServerChatCompletionSSE_Choice[]
---@field created integer
---@field id string
---@field model string
---@field object string -- "chat.completion.chunk"
---@field system_fingerprint string -- deprecated

---@class LlamaServerRawCompletionSSE : LlamaServerSSEBase
---@field content? string|vim.NIL
---@field id_slot integer
---@field index integer
---@field stop? boolean
---@field tokens integer[]
---@field tokens_evaluated integer
---@field tokens_predicted integer

---@class StreamingFrontend
---@field on_parsed_data_sse OnParsedSSE
---@field on_sse_llama_server_timings OnParsedSSE
---@field on_curl_exited_successfully OnCurlExitedSuccessfully
---@field explain_error ExplainError
---@field trace? CurlRequestForTrace
---@field get_flags_wrapper fun(): table<string, any>

---@param request CurlRequest|CurlRequestForTrace
---@param frontend StreamingFrontend
function Curl.spawn(request, frontend)
    request.body.stream = true

    local json_body = vim.json.encode(request.body)
    local options = {
        command = "curl",
        args = {
            "--fail-with-body",
            "-sSL",
            "--no-buffer", -- w/o this curl batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X",
            "POST",
            request:get_url(),
            "-H",
            "Content-Type: application/json",
            "-d",
            json_body
        },
    }

    ---@param data_value string
    function on_data_sse(data_value)
        -- FYI right now this function exists to catch unhandled errors and terminate
        local success, error_message = safely.call(Curl.on_one_data_value, data_value, frontend, request)
        if success then
            return
        end

        -- request stops ASAP, but not immediately
        CurlRequest.terminate(request)
        local message = "Curl.spawn.on_data_sse error_message=" .. vim.inspect(error_message)
        log:error(message)
        frontend.explain_error(message)
    end

    local stdout = vim.uv.new_pipe(false)
    local stderr = vim.uv.new_pipe(false)

    local parser = SSEDataOnlyParser.new(on_data_sse)
    local _stderr_data_parts = {}

    ---@param code integer
    ---@param signal integer
    local function on_exit(code, signal)
        log:trace_on_exit_always(code, signal)
        -- log:trace_on_exit_errors(code, signal) -- less verbose
        local cumulative_stderr = table.concat(_stderr_data_parts, "")
        if cumulative_stderr then
            log:error("Curl.spawn.on_exit cumulative_stderr=", cumulative_stderr)
            -- FYI stderr output has "curl (7)" with exit code == 7 in this case, so don't duplicate those in the message:
            frontend.explain_error(cumulative_stderr)
        end

        -- close before check dregs (b/c might still be data unflushed in STDOUT/ERR)
        stdout:close()
        stderr:close()

        request.handle = nil
        request.pid = nil

        -- flush dregs before on_curl_exited_successfully
        -- - which may depend on, for example, a tool_call in dregs
        local error_text = parser:flush_dregs()
        if error_text then
            local message = "Curl.spawn.on_exit -> flush_dregs -> error_text=" .. vim.inspect(error_text)
            log:error(message)
            frontend.explain_error(message)
        end

        if code == 0 then
            -- FYI this has to come after dregs which may have data used by exit handler!
            --  i.e. triggering tool_calls
            frontend.on_curl_exited_successfully()
        end

        -- FYI review proper uv.spawn cleanup LATER:
        -- - review:   vim.loop.walk(function(handle) print(handle) end)
        --   - I am seeing alot after I just startup nvim... I wonder if some are from my MCP tool comms?
        --   - and what about my timer/schduling for debounced keyboard events to trigger predictions?
        -- - REVIEW OTHER uses of uv.spawn (and timers)... for missing cleanup logic!
    end

    request.handle, request.pid = uv_spawn(options.command, {
        args = options.args,
        stdio = { nil, stdout, stderr },
    }, on_exit)

    ---@param read_error any
    ---@param data? string
    local function on_stdout(read_error, data)
        log:log_if_stdio_read_error("on_stdout", read_error, data)
        -- log:trace_stdio_read_always("on_stdout", read_error, data)

        local no_data = data == nil or data == ""
        if read_error or no_data then
            return
        end
        assert(data ~= nil)

        parser:write(data)
    end
    stdout:read_start(on_stdout)

    ---@param read_error? string
    ---@param data? string
    local function on_stderr(read_error, data)
        log:log_if_stdio_read_error("on_stderr", read_error, data)
        -- log:trace_stdio_read_always("on_stderr", read_error, data)
        if data then
            table.insert(_stderr_data_parts, data)
        end

        local no_data = data == nil or data == ""
        if read_error or no_data then
            return
        end
        assert(data ~= nil)

        -- keep in mind... curl errors will show as text in STDERR
        -- FYI just show individual parts here since the full error message is needed to print one final message, accumulate that for on_exit to print
        local message = "Curl.spawn.on_stderr data=" .. vim.inspect(data) -- info level log for parts
        log:info(message)
        -- TODO see if any errors, if it is useful to see explain_error on each chunk instead of just at end in on_exit... I suspect cumulative_stderr is sufficient for most errors
        -- frontend.explain_error(message)
    end
    stderr:read_start(on_stderr)
end

---@param data_value string
---@param frontend StreamingFrontend
---@param request CurlRequest|CurlRequestForTrace
function Curl.on_one_data_value(data_value, frontend, request)
    -- log:trace("data_value", data_value)

    if data_value == "[DONE]" then
        -- log:trace("DETECTED DONE")
        return
    end

    -- * PARSE DATA VALUE (JSON) => sse_parsed object
    local success, sse_parsed = safely.decode_json(data_value)
    if success and sse_parsed then
        frontend.on_parsed_data_sse(sse_parsed)
        -- FYI not every SSE has to have generated tokens (choices), no need to warn if no parsed value
        completion_logger.log_sse_to_request(sse_parsed, request, frontend)

        if sse_parsed.error then
            -- only confirmed this on llama_server
            -- {"error":{"code":500,"message":"tools param requires --jinja flag","type":"server_error"}}
            local message = "Curl.on_one_data_value sse_parsed.error:" .. vim.inspect(sse_parsed)
            log:error(message)
            frontend.explain_error(message)
        end

        if sse_parsed.timings then
            frontend.on_sse_llama_server_timings(sse_parsed)
        end
    else
        -- PRN in the spirit of triggering events for scenarios, I could add:
        --  frontend:on_data_value_parse_failure(data_value)
        --  but central logging has been fine so far
        log:warn("SSE json parse failed for data_value: ", data_value)
    end
end

return Curl
