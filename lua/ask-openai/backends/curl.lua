local log = require("ask-openai.logs.logger").predictions()
local LastRequest = require("ask-openai.backends.last_request")
local SSEDataOnlyParser = require("ask-openai.backends.sse.data_only_parser")
local RxAccumulatedMessage = require("ask-openai.questions.chat.messages.rx")
local ToolCall = require("ask-openai.questions.chat.tool_call")

local M = {}

---@param request LastRequest
function M.terminate(request)
    LastRequest.terminate(request)
end

---@enum CompletionsEndpoints
_G.CompletionsEndpoints = {
    -- llama-server non-openai:
    completions = "/completions",

    -- OpenAI compatible:
    v1_completions = "/v1/completions",
    v1_chat = "/v1/chat/completions",
}
---@param endpoint CompletionsEndpoints
---@return ExtractGeneratedTextFromChoiceFunction
local function get_extract_generated_text_func(endpoint)
    -- * /completions  CompletionsEndpoints.completions
    --   3rd ExtractGeneratedTextFromChoiceFunction for non-openai /completions endpoint on llama-server
    --     => no sse.choice so I'd have to change how M.on_line_or_lines works to not assume sse.choices
    --     whereas with non-openai /completions it would just use top-level to get text (.content)
    if endpoint == CompletionsEndpoints.v1_completions then
        ---@type ExtractGeneratedTextFromChoiceFunction
        return function(choice)
            --- * /v1/completions
            if choice == nil or choice.text == nil then
                -- just skip if no (first) choice or no text on it (i.e. last SSE is often timing only)
                return ""
            end
            return choice.text
        end
    end

    if endpoint == CompletionsEndpoints.v1_chat then
        ---@type ExtractGeneratedTextFromChoiceFunction
        return function(choice)
            --- * /v1/chat/completions
            -- NOW I have access to request (url, body.model, etc) to be able to dynamically swap in the right SSE parser!
            --   I could even add another function that would handle aggregating and transforming the raw response (i.e. for harmony) into aggregate views (i.e. of thinking and final responses), also trigger events that way
            if choice == nil
                or choice.delta == nil
                or choice.delta.content == nil
                or choice.delta.content == vim.NIL
            then
                return ""
            end
            return choice.delta.content
        end
    end

    if endpoint == CompletionsEndpoints.completions then
        error("TODO /completions endpoint's ExtractGeneratedTextFromChoiceFunction")
    end

    -- TODO CompletionsEndpoints.completions /completions for 3rd ExtractGeneratedTextFromChoiceFunction
    error("Not yet implemented: " .. endpoint)
end

---@class StreamingFrontend
---@field on_generated_text fun(content_chunk: string, sse_parsed: table)
---@field on_sse_llama_server_timings fun(sse_parsed: table)
---@field handle_rx_messages_updated fun()
---@field curl_exited_successfully fun()
---@field explain_error fun(text: string)

---@alias ExtractGeneratedTextFromChoiceFunction fun(first_choice: table): string

---@param body table
---@param base_url string
---@param endpoint CompletionsEndpoints
---@param frontend StreamingFrontend
---@return LastRequest
function M.spawn(body, base_url, endpoint, frontend)
    local url = base_url .. endpoint
    local request = LastRequest:new(body)
    local extract_generated_text = get_extract_generated_text_func(endpoint)

    body.stream = true

    -- log:jsonify_trace("body:", body)

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

    return request
end

---@param data_value string
---@param extract_generated_text ExtractGeneratedTextFromChoiceFunction
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

            --   ? if I don't need this in rewrites, THEN, push this back down into asks via on_generated_text
            M.on_streaming_delta_update_message_history(first_choice, request)
            -- * ONLY AskQuestion uses this:
            frontend.handle_rx_messages_updated()

            -- * ONLY AskRewrite uses this... and that may not change (not sure denormalizer makes sense for rewrites)
            local generated_text = extract_generated_text(first_choice)
            if generated_text and frontend.on_generated_text then
                -- FYI checks for on_generated_text b/c ask doesn't use this interface anymore
                frontend.on_generated_text(generated_text, sse_parsed)
            end
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

--- think of this as denormalizing SSEs => into aggregate RxAccumulatedMessage
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
    request.accumulated_model_response_messages = request.accumulated_model_response_messages or {}

    -- * lookup or create message
    local index_base1 = choice.index + 1
    local rx_message = request.accumulated_model_response_messages[index_base1]
    if rx_message == nil then
        rx_message = RxAccumulatedMessage:new(choice.delta.role, "")
        rx_message.index = choice.index
        rx_message._verbatim_content = ""
        -- assumes contiguous indexes, s/b almost always 0 index only, 1 too with dual tool call IIRC
        request.accumulated_model_response_messages[index_base1] = rx_message
    end

    if choice.delta.content ~= nil and choice.delta.content ~= vim.NIL then
        -- by tracking _verbatim_content, I can trim the end every single time
        -- and if it is not a full match it will show back up once it's past the match point
        rx_message._verbatim_content = (rx_message._verbatim_content or "") .. choice.delta.content
    end

    if choice.delta.reasoning_content ~= nil and choice.delta.reasoning_content ~= vim.NIL then
        rx_message.reasoning_content =
            (rx_message.reasoning_content or "") .. choice.delta.reasoning_content
    end

    if choice.finish_reason ~= nil then
        -- FYI this is vim.NIL on first too
        rx_message.finish_reason = choice.finish_reason -- on last delta per index/role (aka message)
    end

    -- * strip leaked tool call tokens (bug in llama.cpp)
    rx_message.content = rx_message._verbatim_content:gsub("\n<tool_call>\n<function=[%w_]+", "")
    if rx_message.content ~= rx_message._verbatim_content then
        log:error("stripping LEAKED TOOL CALL!")
    end

    local calls = choice.delta.tool_calls
    if not calls then
        return
    end

    -- * parse tool calls (streaming)
    for _, call_delta in ipairs(calls) do
        -- * lookup or create new parsed_call
        local parsed_call = rx_message.tool_calls[call_delta.index + 1]
        if parsed_call == nil then
            -- create ToolCall to populate across SSEs
            parsed_call = ToolCall:new {
                -- assume these fields are always on first SSE for each tool call
                id    = call_delta.id,
                index = call_delta.index,
                type  = call_delta.type,
            }
            table.insert(rx_message.tool_calls, parsed_call)
        end

        local func = call_delta["function"] -- FYI "function" is keyword (lua)
        if func ~= nil then
            parsed_call["function"] = parsed_call["function"] or {}

            -- * function.name is entirely in first delta (in my testing)
            if func.name ~= nil then
                --   => if that changes, add unit tests to verify observed splits
                parsed_call["function"].name = func.name
            end

            -- * funtion.arguments is split across deltas
            if func.arguments ~= nil then
                -- accumuluate each chunk
                parsed_call["function"].arguments =
                    (parsed_call["function"].arguments or "")
                    .. func.arguments
            end
        end
    end
end

return M
