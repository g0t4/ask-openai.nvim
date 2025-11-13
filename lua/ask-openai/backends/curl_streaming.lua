local log = require("ask-openai.logs.logger").predictions()
local LastRequest = require("ask-openai.backends.last_request")
local SSEStreamParser = require("ask-openai.backends.sse.stream.parser")
local uv = vim.uv

local M = {}

---@param request LastRequest
function M.terminate(request)
    LastRequest.terminate(request)
end

function M.reusable_curl_seam(body, url, frontend, extract_generated_text, backend)
    local request = LastRequest:new(body)

    body.stream = true
    local json = vim.json.encode(body)
    log:json_info("body:", json)

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
    -- -- PRN use configuration/caching for this (various providers from original cmdline help feature)
    -- -- for now, just uncomment this when testing:
    -- api_key = os.getenv("OPENAI_API_KEY")
    -- if api_key then
    --     table.insert(options.args, "-H")
    --     table.insert(options.args, "Authorization: Bearer " .. api_key)
    -- end

    -- PRN could use bat -l sh for this one:
    -- log:warn("curl args: ", table.concat(options.args, " "))

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    options.on_exit = function(code, signal)
        log:trace_on_exit_always(code, signal)
        -- log:trace_on_exit_errors(code, signal) -- less verbose

        if code ~= nil and code ~= 0 then
            log:error("spawn - non-zero exit code: '" .. code .. "' Signal: '" .. signal .. "'")
            -- DO NOT add frontend handler just to have it log again!
        else
            frontend.curl_request_exited_successful_on_zero_rc()
        end
        stdout:close()
        stderr:close()

        -- this shoudl be attacked to a specific request (not any module)
        -- clear out refs
        request.handle = nil
        request.pid = nil
    end

    request.handle, request.pid = uv.spawn(options.command, {
        args = options.args,
        stdio = { nil, stdout, stderr },
    }, options.on_exit)


    function data_value_handler(data_value)
        -- TODO extract error handling: both the xpcall + traceback, and the print_error func below
        -- FYI good test case is to comment out: choice.delta.content == vim.NIL in extract_generated_text
        local success, result = xpcall(function()
            M.on_line_or_lines(data_value, extract_generated_text, frontend, request)
        end, function(e)
            -- otherwise only get one line from the traceback (frame that exception was thrown)
            return debug.traceback(e, 3)
        end)

        if not success then
            M.terminate(request)

            -- FAIL EARLY, accept NO unexpected exceptions in completion parsing
            -- by the way the request will go a bit longer but it will stop ASAP
            -- important part is to alert me
            log:error("Terminating curl_streaming due to unhandled exception", result)

            local function print_error(message)
                -- replace literals so traceback is pretty printed (readable)
                message = tostring(message):gsub("\\n", "\n"):gsub("\\t", "\t")
                -- with traceback lines... this will trigger hit-enter mode
                --  therefore the error will not disappear into message history!
                -- ErrorMsg makes it red
                vim.api.nvim_echo({ { message, "ErrorMsg" } }, true, {})
            end

            vim.schedule(function()
                print_error("Terminating curl_streaming due to unhandled exception" .. tostring(result))
            end)
        end
    end

    -- PRN request._sse_parser = parser -- currently closure is sufficient for all expected use cases
    local parser = SSEStreamParser.new(data_value_handler)
    options.on_stdout = function(read_error, data)
        -- log:trace_stdio_read_errors("on_stdout", err, data)
        log:trace_stdio_read_always("on_stdout", read_error, data)

        local no_data = data == nil or data == ""
        if read_error or no_data then
            -- reminder, rely on trace above
            return
        end

        parser:write(data)
    end
    uv.read_start(stdout, options.on_stdout)

    options.on_stderr = function(read_error, data)
        log:trace_stdio_read_always("on_stderr", read_error, data)
        -- log:trace_stdio_read_errors("on_stderr", err, data)

        local no_data = data == nil or data == ""
        if read_error or no_data then
            -- reminder, rely on trace above
            return
        end

        -- keep in mind... curl errors will show as text in STDERR
        frontend.on_stderr_data(data)
    end
    uv.read_start(stderr, options.on_stderr)

    return request
end

function M.on_line_or_lines(data_value, extract_generated_text, frontend, request)
    -- log:trace("data_value", data_value)

    if data_value == "[DONE]" then
        log:trace("DETECTED DONE")
        goto ignore_done
    end

    local success, sse_parsed = pcall(vim.json.decode, data_value)

    if success and sse_parsed then
        if sse_parsed.choices and sse_parsed.choices[1] then
            local first_choice = sse_parsed.choices[1]
            -- OK if no first_choice

            -- IIRC this is only ask questions currently
            --   ? if I don't need this in rewrites, THEN, push this back down into asks via on_generated_text
            M.on_delta_update_message_history(first_choice, request)
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
            -- FYI do not log again here
            frontend.on_sse_llama_server_error_explanation(sse_parsed)
        end

        if sse_parsed.timings then
            frontend.on_sse_llama_server_timings(sse_parsed)
        end
    else
        log:warn("SSE json parse failed for data_value: ", data_value)
    end

    ::ignore_done::
end

---@class OpenAIChoice
---@field delta OpenAIChoiceDelta
---@field finish_reason string|nil
---@field index integer

---@class OpenAIChoiceDelta
---@field content string|nil
---@field role string|nil
---@field tool_calls OpenAIChoiceDeltaToolCall[]|nil

---@class OpenAIChoiceDeltaToolCall
---@field index integer
---@field id string|nil
---@field type string|nil
---@field function OpenAIChoiceDeltaToolCallFunction|nil

---@class OpenAIChoiceDeltaToolCallFunction
---@field name string|nil
---@field arguments string|nil

---@param choice OpenAIChoice|nil
function M.on_delta_update_message_history(choice, request)
    -- *** this is a DENORMALIZER (AGGREGATOR) - CQRS style
    -- rebuilds message as if sent `stream: false`
    -- for message history / follow up

    if choice == nil or choice.delta == nil then
        log:trace("[WARN] skipping b/c choice/choice.delta is nil: '" .. vim.inspect(choice) .. "'")
        return
    end
    request.messages = request.messages or {}

    -- lookup or create message
    local msg_lookup = choice.index + 1
    local message = request.messages[msg_lookup]
    if message == nil then
        message = {
            index = choice.index,
            role = choice.delta.role,
            verbatim_content = "",
        }
        -- assumes contiguous indexes, s/b almost always 0 index only, 1 too with dual tool call IIRC
        request.messages[msg_lookup] = message
    end

    if choice.delta.content ~= nil then
        if choice.delta.content == vim.NIL then
            log:error("TODO FIND OUT IF THIS MATTERS - my guess is NO but still check - content is null (in json) or vim.NIL in parsed on first delta (when using llama-server + gpt-oss)?",
                vim.inspect(choice))
        else
            -- by tracking verbatim_content, I can trim the end every single time and if it is not a full match it will show back up once it's past the match point
            message.verbatim_content = (message.verbatim_content or "") .. choice.delta.content
        end
    end

    if choice.finish_reason ~= nil then
        -- FYI this is vim.NIL on first too
        message.finish_reason = choice.finish_reason -- on last delta per index/role (aka message)
    end

    -- TODO what other tool_call styles are left in, there were others
    message.content = message.verbatim_content:gsub("\n<tool_call>\n<function=[%w_]+", "")
    if message.content ~= message.verbatim_content then
        log:error("stripping LEAKED TOOL CALL!")
    end

    -- vim.print("original", message.original_content)
    -- vim.print("truncated", message.content)

    local calls = choice.delta.tool_calls
    if calls then
        for _, tool_call_delta in ipairs(calls) do
            -- * lookup or create parsed_call
            -- TODO create a typed class for parsed_call?
            local parsed_call = message.tool_calls[tool_call_delta.index + 1]
            if parsed_call == nil then
                parsed_call = {
                    -- assuming these are always on first delta per message
                    id    = tool_call_delta.id,
                    index = tool_call_delta.index,
                    type  = tool_call_delta.type,
                }
                table.insert(message.tool_calls, parsed_call)
            end

            local func = tool_call_delta["function"]
            if func ~= nil then
                parsed_call["function"] = parsed_call["function"] or {}
                if func.name ~= nil then
                    -- first delta has full name in my testing
                    parsed_call["function"].name = func.name
                end
                if func.arguments ~= nil then
                    parsed_call["function"].arguments =
                        (parsed_call["function"].arguments or "")
                        .. func.arguments
                end
            end
        end
    end
end

return M
