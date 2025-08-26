local log = require("ask-openai.logs.logger").predictions()
local LastRequest = require("ask-openai.backends.last_request")
local uv = vim.uv

local M = {}

---@param request LastRequest
function M.terminate(request)
    LastRequest.terminate(request)
end

function M.reusable_curl_seam(body, url, frontend, parse_choice, backend)
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

            -- todo what logic do I want to NOT call handle_request_failed here?
            frontend.handle_request_failed(code)
        else
            frontend.handle_request_completed()
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

    options.on_stdout = function(read_error, data)
        log:trace_stdio_read_always("on_stdout", read_error, data)
        -- log:trace_stdio_read_errors("on_stdout", err, data)

        local no_data = data == nil or data == ""
        if read_error or no_data then
            -- reminder, rely on trace above
            return
        end

        -- TODO extract error handling: both the xpcall + traceback, and the print_error func below
        -- FYI good test case is to comment out: choice.delta.content == vim.NIL in parse_choice
        local success, result = xpcall(function()
            M.on_line_or_lines(data, parse_choice, frontend, request)
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

M.on_line_or_lines = function(data, parse_choice, frontend, request)
    -- SSE = Server-Sent Event
    -- split on lines first (each SSE can have 0+ "event" - one per line)

    for ss_event in data:gmatch("[^\r\n]+") do
        -- log:trace("ss_event" ss_event)

        if ss_event:match("^data:%s*%[DONE%]$") then
            goto ignore_done
        end

        --  strip leading "data: " (if present)
        local event_json = ss_event
        if ss_event:sub(1, 6) == "data: " then
            event_json = ss_event:sub(7)
        end
        local success, sse_parsed = pcall(vim.json.decode, event_json)

        if success and sse_parsed then
            if sse_parsed.choices and sse_parsed.choices[1] then
                local first_choice = sse_parsed.choices[1]
                -- OK if no first_choice

                -- IIUC this is just message history related
                M.on_delta_update_message_history(first_choice, frontend, request)
                frontend.handle_messages_updated()

                -- KEEP THIS FOR rewrite to keep working (until its ported to use denormalizer):
                local chunk = parse_choice(first_choice)
                if chunk and frontend.process_chunk then
                    -- FYI checks for process_chunk b/c ask doesn't use this interface anymore
                    -- TODO RENAME process_chunk
                    frontend.process_chunk(chunk, sse_parsed)
                end
            end
            -- FYI not every SSE has to have generated tokens (choices), no need to warn

            if sse_parsed.timings then
                frontend.on_sse_llama_server_timings(sse_parsed)
            end
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end

        ::ignore_done::
    end
end

function M.on_delta_update_message_history(choice, frontend, request)
    -- *** this is a DENORMALIZER (AGGREGATOR) - CQRS style
    -- rebuilds message as if sent `stream: false`
    -- for message history / follow up
    -- TODO later, use to update the ChatWindow
    --    == rip out the original pathways that called process_chunk / etc
    --    KEEP DeltaArrived signal though (refreshes/rebuilds ChatWindow)


    -- FYI for now lets only do this for oai_chat (which uses delta in the choice)...
    --   oai_completions doesn't have delta, I would need to look at its examples before I try to fit it in here...
    --   I probably should have a diff aggregator for each backend's streaming format
    --   FYI I called oai_chat the 'middleend' briefly, this could be passed by the middleend to on_chunk
    if request == nil then
        log:trace("[WARN] on_delta not implemented")
        -- TODO REMOVE WHEN TESTS/CODE ARE UPDATED
        return
    end
    if type(request) == "string" and request:match("^TODO") then
        log:trace("[WARN] on_delta not implemented for some tests")
        -- TODO REMOVE WHEN TESTS ARE UPDATED
        return
    end

    if choice == nil or choice.delta == nil then
        log:trace("[WARN] skipping b/c choice/choice.delta is nil: '" .. vim.inspect(choice) .. "'")
        return
    end
    if request.messages == nil then
        -- TODO move this to a request type?
        request.messages = {}
    end

    -- lookup or create message
    local msg_lookup = choice.index + 1
    local message = request.messages[msg_lookup]
    if message == nil then
        message = {
            index = choice.index,
            role = choice.delta.role,
        }
        -- assumes contiguous indexes, s/b almost always 0 index only, 1 too with dual tool call IIRC
        -- TODO add tests for index/role lookups too and be safe about this
        request.messages[msg_lookup] = message
    end

    if choice.delta.content ~= nil then
        if choice.delta.content == vim.NIL then
            log:error("TODO FIND OUT IF THIS MATTERS - my guess is NO but still check - content is null (in json) or vim.NIL in parsed on first delta (when using llama-server + gpt-oss)?",
                vim.inspect(choice))
            -- TODO return?
        else
            message.content = (message.content or "") .. choice.delta.content
        end
    end

    if choice.finish_reason ~= nil then
        -- FYI this is vim.NIL on first too
        -- TODO is finish_reason per message OR the entire request!?
        -- PRN throw if finish_reason already set?
        message.finish_reason = choice.finish_reason -- on last delta per index/role (aka message)
    end

    calls = choice.delta.tool_calls
    if calls then
        message.tool_calls = (message.tool_calls or {})
        for _, call_delta in ipairs(calls) do
            -- TODO test stream case w/ vllm b/c non stream case is easier
            -- for now just assume entirely new tool call each time... will fix this with a test of streaming later
            parsed_call = message.tool_calls[call_delta.index + 1]
            -- PRN lookup message by index # and dont rely on contiguous index values?
            if parsed_call == nil then
                parsed_call = {
                    -- assuming these are always on first delta per message
                    id    = call_delta.id,
                    index = call_delta.index,
                    type  = call_delta.type,
                }
                table.insert(message.tool_calls, parsed_call)
            end
            func = call_delta["function"]
            if func ~= nil then
                parsed_call["function"] = parsed_call["function"] or {}
                if func.name ~= nil then
                    parsed_call["function"].name = func.name
                end
                if func.arguments ~= nil then
                    -- technically, need a test to validate nil check here but just do it for now
                    current = parsed_call["function"].arguments or ""
                    parsed_call["function"].arguments = (current .. func.arguments)
                end
            end
        end
    end
end

-- PRN does vllm have both finish_reason and stop_reason?
--   wait to handle it until actually needed
--   probably coalesce finish_reason|stop_reason to keep it transparent

return M
