local log = require("ask-openai.logs.logger").predictions()
local completion_logger = require("ask-openai.logs.completion_logger")
local CurlRequest = require("ask-openai.backends.curl_request")
local SSEDataOnlyParser = require("ask-openai.backends.sse.data_only_parser")
local safely = require("ask-openai.helpers.safely")
local json = require('dkjson')

local Curl = {}

---@enum CompletionsEndpoints
_G.CompletionsEndpoints = {
    -- llama-server non-openai:
    llamacpp_completions = "/completions",

    -- OpenAI compatible:
    oai_v1_completions = "/v1/completions",
    oai_v1_chat_completions = "/v1/chat/completions",

    -- ollama specific
    ollama_api_generate = "/api/generate",
    ollama_api_chat = "/api/chat",
}

---@alias OnParsedSSE fun(sse_parsed: table)
---@alias ExplainError fun(text: string)
---@alias OnCurlExitedSuccessfully fun()

---@class StreamingFrontend
---@field on_parsed_data_sse OnParsedSSE
---@field on_sse_llama_server_timings OnParsedSSE
---@field on_curl_exited_successfully OnCurlExitedSuccessfully
---@field explain_error ExplainError
---@field thread? CurlRequestForThread

---@param request CurlRequest|CurlRequestForThread
---@param frontend StreamingFrontend
function Curl.spawn(request, frontend)
    request.body.stream = true

    completion_logger.write_messages_jsonl(request, frontend)

    local json_body = vim.json.encode(request.body)
    local options = {
        command = "curl",
        args = {
            "--fail-with-body",
            "-sSL",
            "--no-buffer", -- w/o this curl batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            request:get_url(),
            "-H", "Content-Type: application/json",
            "-d", json_body
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
        frontend.explain_error("Abort... unhandled exception in curl: " .. tostring(error_message))
    end

    local stdout = vim.uv.new_pipe(false)
    local stderr = vim.uv.new_pipe(false)

    local parser = SSEDataOnlyParser.new(on_data_sse)

    ---@param code integer
    ---@param signal integer
    local function on_exit(code, signal)
        -- log:trace_on_exit_always(code, signal)
        log:trace_on_exit_errors(code, signal) -- less verbose

        -- close before check dregs (b/c might still be data unflushed in STDOUT/ERR)
        stdout:close()
        stderr:close()

        request.handle = nil
        request.pid = nil

        -- flush dregs before on_curl_exited_successfully
        -- - which may depend on, for example, a tool_call in dregs
        local error_text = parser:flush_dregs()
        if error_text then
            frontend.explain_error(error_text)
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
        -- - REVIEW OTHER uses of uv.spawn (and timers)... for missing cleanup logic!)
    end

    request.handle, request.pid = vim.uv.spawn(options.command,
        ---@diagnostic disable-next-line: missing-fields
        {
            args = options.args,
            stdio = { nil, stdout, stderr },
        },
        on_exit)

    ---@param read_error any
    ---@param data? string
    local function on_stdout(read_error, data)
        log:trace_stdio_read_errors("on_stdout", read_error, data)
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
        log:trace_stdio_read_errors("on_stderr", read_error, data)
        -- log:trace_stdio_read_always("on_stderr", read_error, data)

        local no_data = data == nil or data == ""
        if read_error or no_data then
            return
        end
        assert(data ~= nil)

        -- keep in mind... curl errors will show as text in STDERR
        frontend.explain_error(data)
    end
    stderr:read_start(on_stderr)
end

---@param data_value string
---@param frontend StreamingFrontend
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
            -- DO NOT LOG HERE TOO
            frontend.explain_error("found error on what looks like an SSE:" .. vim.inspect(sse_parsed))
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
