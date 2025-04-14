local log = require("ask-openai.prediction.logger").predictions()
local LastRequest = require("ask-openai.backends.last_request")
local uv = vim.uv

local M = {}

---@param request LastRequest
function M.terminate(request)
    LastRequest.terminate(request)
end

M.on_chunk = function(data, parse_choice, frontend, request)
    local chunk, finish_reason, tool_calls_s = M.parse_SSEs(data, parse_choice, frontend, request)
    if chunk then
        -- TODO combine chunks too so the request has the final combined text
        -- - right now I just show the chunks one by one
        -- - later I'll need this for message history
        -- - makes sense to coalesce here
        frontend.process_chunk(chunk)
    end
    if tool_calls_s then
        local flattened_calls = {}
        for _, tool_calls in ipairs(tool_calls_s) do
            for _, tool_call in ipairs(tool_calls) do
                flattened_calls[#flattened_calls + 1] = tool_call
            end
        end
        frontend.process_tool_calls(flattened_calls)
    end
    if finish_reason ~= nil and finish_reason ~= vim.NIL then
        -- TODO? pass combined chunk and tool_calls here?
        -- PRN any final processing (i.e. tool fallback)
        frontend.process_finish_reason(finish_reason)
    end
end

function M.reusable_curl_seam(body, url, frontend, parse_choice, backend)
    local request = LastRequest:new(body)

    body.stream = true
    local json = vim.fn.json_encode(body)
    log:json_info("body:", json)

    local options = {
        command = "curl",
        args = {
            "-fsSL",
            "--no-buffer", -- w/o this curl batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            url,
            "-H", "Content-Type: application/json",
            "-d", json
        },
    }
    -- PRN could use bat -l sh for this one:
    log:warn("curl args: ", table.concat(options.args, " "))

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    options.on_exit = function(code, signal)
        log:trace_on_exit_always(code, signal)
        -- log:trace_on_exit_errors(code, signal) -- less verbose

        if code ~= nil and code ~= 0 then
            log:error("spawn - non-zero exit code: '" .. code .. "' Signal: '" .. signal .. "'")

            -- todo what logic do I want to NOT call request_failed here?
            frontend.request_failed(code)
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

        M.on_chunk(data, parse_choice, frontend, request)
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

--- @param data string
--- @return string|nil text, string|nil finish_reason, table|nil tool_calls_s
function M.parse_SSEs(data, parse_choice, frontend, request)
    -- SSE = Server-Sent Event
    -- split on lines first (each SSE can have 0+ "event" - one per line)

    local chunk = nil -- combine all chunks into one string and check for done
    local finish_reason = nil -- only ever one for entire request
    local tool_calls_s = {} -- can be multiple
    -- for lack of a better name right now, call it tool_calls_s so it at least stands out

    for ss_event in data:gmatch("[^\r\n]+") do
        -- PERHAPS I should be returning multiple then instead of adding them below?

        if ss_event:match("^data:%s*%[DONE%]$") then
            -- ignore the [DONE] line, nothing to parse
            goto continue
        end

        -- TODO shouldn't be aggregating across deltas w/o looking at role/index!
        --    just worked out fine that I never have differing values for role/index so far

        --  strip leading "data: " (if present)
        local event_json = ss_event
        if ss_event:sub(1, 6) == "data: " then
            event_json = ss_event:sub(7)
        end
        local success, parsed = pcall(vim.json.decode, event_json)

        if success and parsed and parsed.choices and parsed.choices[1] then
            local first_choice = parsed.choices[1]

            -- btw everything outside of the delta is just its package for delivery, not needed after I get the delta out
            M.on_delta(first_choice, parse_choice, frontend, request)


            -- TODO eventually I will rip out most if not all of the following
            --   this method will become ONLY the parser...
            --   the aggregator will be on_delta
            --   and I won't be doing any chunk/tool aggregation logic below!
            --   and all events can be built off of the on_delta event

            finish_reason = first_choice.finish_reason
            if finish_reason ~= nil and finish_reason ~= vim.NIL then
                -- FYI merely a warning when new finish_reason is encountered (i.e. today tool_calls)
                if finish_reason ~= "stop"
                    and finish_reason ~= "length"
                    and finish_reason ~= "tool_calls"
                then
                    log:warn("[WARN] unexpected finish_reason: '" .. finish_reason .. "'")
                end
            end

            local new_chunk
            new_chunk, tool_calls = parse_choice(first_choice)
            -- PRN if any good reason to do so.. can return  chunks (not chunk concatenated):
            chunk = (chunk or "") .. (new_chunk or "")
            -- use tests to add conditions like vim.NIL, nil for:
            table.insert(tool_calls_s, tool_calls)
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end

        ::continue::
    end
    return chunk, finish_reason, tool_calls_s
end

function M.on_delta(choice, parse_choice, frontend, request)
    -- *** this is a DENORMALIZER (AGGREGATOR) - CQRS style
    -- choice == {"index":0,"delta":{"role":"assistant","content":""}

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
        message.content = (message.content or "") .. choice.delta.content
    end

    if choice.finish_reason ~= nil then
        -- TODO is finish_reason per message OR the entire request!?
        -- PRN throw if finish_reason already set?
        message.finish_reason = choice.finish_reason -- on last delta per index/role (aka message)
    end

    calls = choice.delta.tool_calls
    if calls then
        message.tool_calls = (message.tool_calls or {})
        for _, call in ipairs(calls) do
            -- TODO test stream case w/ vllm b/c non stream case is easier
            -- for now just assume entirely new tool call each time... will fix this with a test of streaming later
            parsed_call = {
                id           = call.id,
                index        = call.index,
                type         = call.type,
                ["function"] = {
                    name = call["function"].name,
                }

            }
            table.insert(message.tool_calls, parsed_call)
        end
    end

    -- this is the new pathway that will rebuild the full message (as if sent stream: false)
    --   will be used to have accurate message history to send for follow up/tool results/etc

    -- later, I can use this to update the UI for what I do with chunks currently
    --    that will entail redrawing message history (or at least part of it for the current messages being streamed)

    -- TODO when I encounter a finish_reason or other stop signal, make sure to reset tmp_current_messages!
end

-- PRN does vllm have both finish_reason and stop_reason?
--   wait to handle it until actually needed
--   probably coalesce finish_reason|stop_reason to keep it transparent

return M
