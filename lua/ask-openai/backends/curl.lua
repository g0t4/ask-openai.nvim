local log = require("ask-openai.logs.logger").predictions()
local LastRequest = require("ask-openai.backends.last_request")
local SSEDataOnlyParser = require("ask-openai.backends.sse.data_only_parser")
local RxAccumulatedMessage = require("ask-openai.questions.chat.messages.rx")
local ToolCall = require("ask-openai.questions.chat.tool_call")

local Curl = {}

---@enum CompletionsEndpoints
_G.CompletionsEndpoints = {
    -- llama-server non-openai:
    completions = "/completions",

    -- OpenAI compatible:
    v1_completions = "/v1/completions",
    v1_chat = "/v1/chat/completions",
}

---@alias OnGeneratedText fun(sse_parsed: table)

---@class StreamingFrontend
---@field on_parsed_data_sse_with_choice OnGeneratedText
---@field on_sse_llama_server_timings fun(sse_parsed: table)
---@field handle_rx_messages_updated fun()
---@field curl_exited_successfully fun()
---@field explain_error fun(text: string)


---@param request LastRequest|LastRequestForThread
---@param frontend StreamingFrontend
function Curl.spawn(request, frontend)
    request.body.stream = true

    local json = vim.json.encode(request.body)
    local options = {
        command = "curl",
        args = {
            "--fail-with-body",
            "-sSL",
            "--no-buffer", -- w/o this curl batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            request:get_url(),
            "-H", "Content-Type: application/json",
            "-d", json
        },
    }

    ---@param data_value string
    function on_data_sse(data_value)
        local success, error_message = xpcall(function()
            Curl.on_line_or_lines(data_value, frontend, request)
        end, function(e)
            -- otherwise only get one line from the traceback frame
            return debug.traceback(e, 3)
        end)

        if success then
            return
        end

        -- request stops ASAP, but not immediately
        LastRequest.terminate(request)
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

        -- flush dregs before curl_exited_successfully
        -- - which may depend on, for example, a tool_call in dregs
        local error_text = parser:flush_dregs()
        if error_text then
            frontend.explain_error(error_text)
        end

        if code == 0 then
            -- FYI this has to come after dregs which may have data used by exit handler!
            --  i.e. triggering tool_calls
            frontend.curl_exited_successfully()
        end
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

        -- keep in mind... curl errors will show as text in STDERR
        frontend.explain_error(data)
    end
    stderr:read_start(on_stderr)
end

---@param data_value string
---@param frontend StreamingFrontend
---@param request LastRequest|LastRequestForThread
function Curl.on_line_or_lines(data_value, frontend, request)
    -- log:trace("data_value", data_value)

    if data_value == "[DONE]" then
        -- log:trace("DETECTED DONE")
        return
    end

    local success, sse_parsed = pcall(vim.json.decode, data_value)
    if success and sse_parsed then
        -- TODO when I expand support to llama-server's /completions endpoint, I can either add a new event on_parsed_data_sse (no choices required) or broaden existing handler:
        if sse_parsed.choices and sse_parsed.choices[1] then
            frontend.on_parsed_data_sse_with_choice(sse_parsed)
        end
        -- FYI not every SSE has to have generated tokens (choices), no need to warn if no parsed value

        if sse_parsed.error then
            -- only confirmed this on llama_server, rename if other backends follow suit
            -- {"error":{"code":500,"message":"tools param requires --jinja flag","type":"server_error"}}
            -- DO NOT LOG HERE TOO
            frontend.explain_error("found error on what looks like an SSE:" .. vim.inspect(sse_parsed))
        end

        if sse_parsed.timings then
            frontend.on_sse_llama_server_timings(sse_parsed)
        end
    else
        log:warn("SSE json parse failed for data_value: ", data_value)
    end
end

return Curl
