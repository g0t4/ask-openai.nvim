local log = require("ask-openai.logs.logger").predictions()
local LastRequest = require("ask-openai.backends.last_request")
local SSEDataOnlyParser = require("ask-openai.backends.sse.data_only_parser")
local ChatMessage = require("ask-openai.questions.chat.message")
local ToolCall = require("ask-openai.questions.chat.tool_call")
local uv = vim.uv

local M = {}

---@param request LastRequest
function M.terminate(request)
    LastRequest.terminate(request)
end

---@class StreamingFrontend
---@field on_generated_text fun(content_chunk: string, sse_parsed: table)
---@field on_sse_llama_server_timings fun(sse_parsed: table)
---@field handle_messages_updated fun()
---@field curl_exited_successfully fun()
---@field explain_error fun(text: string)

---@alias ExtractGeneratedTextFunction fun(first_choice: table): string

---@param body table
---@param url string
---@param frontend StreamingFrontend
---@param extract_generated_text ExtractGeneratedTextFunction
---@param backend CurlMiddle -- TODO remove backend unused param?
---@return LastRequest
function M.reusable_curl_seam(body, url, frontend, extract_generated_text, backend)
    local request = LastRequest:new(body)

    body.stream = true

    -- log:jsonify_compact_trace("body:", body)
    log:jsonify_trace("body:", body)

    local json = vim.json.encode(body)
    local options = {
        command = "curl",
        args = {
            "--fail-with-body",
            "-sSL",
            "--no-buffer", -- w/o this curl batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            url,
            "-H", "Content-Type: application/json",
            "-d", json
        },
    }

    ---@param data_value string
    function on_data_sse(data_value)
        local success, error_message = xpcall(function()
            M.on_line_or_lines(data_value, frontend, extract_generated_text, request)
        end, function(e)
            -- otherwise only get one line from the traceback frame
            return debug.traceback(e, 3)
        end)

        if success then
            return
        end

        -- request stops ASAP, but not immediately
        M.terminate(request)
        frontend.explain_error("Abort... unhandled exception in curl_streaming: " .. tostring(error_message))
    end

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

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

    request.handle, request.pid = uv.spawn(options.command,
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

    return request
end

---@param data_value string
---@param extract_generated_text ExtractGeneratedTextFunction
---@param frontend StreamingFrontend
---@param request LastRequest
function M.on_line_or_lines(data_value, frontend, extract_generated_text, request)
    -- log:trace("data_value", data_value)

    if data_value == "[DONE]" then
        -- log:trace("DETECTED DONE")
        return
    end

    local success, sse_parsed = pcall(vim.json.decode, data_value)
    if success and sse_parsed then
        if sse_parsed.choices and sse_parsed.choices[1] then
            local first_choice = sse_parsed.choices[1]
            -- OK if no first_choice

            -- IIRC this is only ask questions currently
            --   ? if I don't need this in rewrites, THEN, push this back down into asks via on_generated_text
            M.on_streaming_delta_update_message_history(first_choice, request)
            frontend.handle_messages_updated()

            -- only rewrite uses this... and that may not change (not sure denormalizer makes sense for rewrites)
            local generated_text = extract_generated_text(first_choice)
            if generated_text and frontend.on_generated_text then
                -- FYI checks for on_generated_text b/c ask doesn't use this interface anymore
                frontend.on_generated_text(generated_text, sse_parsed)
            end

            -- PRN on_reasoning_text ... choice.delta.reasoning?/thinking? ollama splits this out, IIUC LM Studio does too... won't work if using harmony format with gpt-oss that isnt' parsed
        end
        -- FYI not every SSE has to have generated tokens (choices), no need to warn

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

---@param choice OpenAIChoice|nil
---@param request LastRequest
function M.on_streaming_delta_update_message_history(choice, request)
    -- *** this is a DENORMALIZER (AGGREGATOR) - CQRS style
    -- rebuilds message as if sent `stream: false`
    -- for message history / follow up

    if choice == nil or choice.delta == nil then
        log:trace("[WARN] skipping b/c choice/choice.delta is nil: '" .. vim.inspect(choice) .. "'")
        return
    end
    request.response_messages = request.response_messages or {}

    -- * lookup or create message
    local index_base1 = choice.index + 1
    local message = request.response_messages[index_base1]
    if message == nil then
        message = ChatMessage:new(choice.delta.role, "")
        message.index = choice.index
        message._verbatim_content = ""
        -- assumes contiguous indexes, s/b almost always 0 index only, 1 too with dual tool call IIRC
        request.response_messages[index_base1] = message
    end

    if choice.delta.content ~= nil and choice.delta.content ~= vim.NIL then
        -- by tracking _verbatim_content, I can trim the end every single time
        -- and if it is not a full match it will show back up once it's past the match point
        message._verbatim_content = (message._verbatim_content or "") .. choice.delta.content
    end

    if choice.delta.reasoning_content ~= nil and choice.delta.reasoning_content ~= vim.NIL then
        message.reasoning_content =
            (message.reasoning_content or "") .. choice.delta.reasoning_content
    end

    if choice.finish_reason ~= nil then
        -- FYI this is vim.NIL on first too
        message.finish_reason = choice.finish_reason -- on last delta per index/role (aka message)
    end

    -- * strip leaked tool call tokens (bug in llama.cpp)
    message.content = message._verbatim_content:gsub("\n<tool_call>\n<function=[%w_]+", "")
    if message.content ~= message._verbatim_content then
        log:error("stripping LEAKED TOOL CALL!")
    end

    -- * parse tool calls
    local calls = choice.delta.tool_calls
    if not calls then
        return
    end
    for _, call_delta in ipairs(calls) do
        -- * lookup or create new parsed_call
        local parsed_call = message.tool_calls[call_delta.index + 1]
        if parsed_call == nil then
            -- first time, create ToolCall so it can be populated across streaming SSEs
            parsed_call = ToolCall:new {
                -- assuming these are always on first delta per message
                id    = call_delta.id,
                index = call_delta.index,
                type  = call_delta.type,
            }
            table.insert(message.tool_calls, parsed_call)
        end

        local func = call_delta["function"] -- "function" is a keyword in lua, so must wrap it to access it
        if func ~= nil then
            -- FYI different fields are populated across deltas, so you must use/append to what already exists
            parsed_call["function"] = parsed_call["function"] or {}
            if func.name ~= nil then
                -- first delta has full name in my testing (not appending chunks, if I encounter split name then add test for it and update here)
                parsed_call["function"].name = func.name
            end
            if func.arguments ~= nil then
                -- append latest chunks for the arguments string (streaming chunks like content/reasoning)
                parsed_call["function"].arguments =
                    (parsed_call["function"].arguments or "")
                    .. func.arguments
            end
        end
    end
end

return M
