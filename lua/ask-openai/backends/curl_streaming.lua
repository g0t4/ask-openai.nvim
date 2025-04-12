local log = require("ask-openai.prediction.logger").predictions()
local mcp = require("ask-openai.prediction.tools.mcp")
local uv = vim.uv

local M = {}

function M.terminate(request)
    -- TODO move this onto a request class?
    --  and if its on request, the request can be marked w/ a status instead of nil for values
    -- PRN add interface to frontend to be notified when a request is aborted or its status changes in general
    if request == nil or request.handle == nil then
        return
    end

    local handle = request.handle
    local pid = request.pid
    request.handle = nil
    request.pid = nil
    if handle ~= nil and not handle:is_closing() then
        log:trace("Terminating process, pid: ", pid)

        handle:kill("sigterm")
        handle:close()
        -- FYI ollama should show that connection closed/aborted
    end
    -- TODO! see :h uv.spawn() for using uv.shutdown/uv.close? and fallback to kill, or does it matter?
end

function M.reusable_curl_seam(body, url, frontend, choice_text)
    local request = {
        body = body
    }

    -- FYI only valid for /api/chat, /v1/chat/completions (not /v1/completions and /api/generate)
    -- TODO toggle to control
    body.tools = mcp.openai_tools()

    body.stream = true
    local json = vim.fn.json_encode(body)
    log:json_info(json)

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
        log:trace_stdio_read("on_stdout", read_error, data)
        -- log:trace_stdio_read_errors("on_stdout", err, data)

        local no_data = data == nil or data == ""
        if read_error or no_data then
            -- reminder, rely on trace above
            return
        end

        local chunk, finish_reason, tool_calls = M.sse_to_chunk(data, choice_text)
        if chunk then
            frontend.process_chunk(chunk)
        end
        if tool_calls then
            frontend.process_tool_calls(tool_calls)
        end
        if finish_reason ~= nil and finish_reason ~= vim.NIL then
            frontend.process_finish_reason(finish_reason)
        end
    end
    uv.read_start(stdout, options.on_stdout)

    options.on_stderr = function(read_error, data)
        log:trace_stdio_read("on_stderr", read_error, data)
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
--- @return string|nil text, string|nil finish_reason, table|nil tool_calls
function M.sse_to_chunk(data, choice_text)
    -- SSE = Server-Sent Event
    -- split on lines first (each SSE can have 0+ "event" - one per line)

    local chunk = nil -- combine all chunks into one string and check for done
    local finish_reason = nil
    local tool_calls = nil
    for ss_event in data:gmatch("[^\r\n]+") do
        if ss_event:match("^data:%s*%[DONE%]$") then
            -- done, courtesy last event... mostly ignore b/c finish_reason already comes on the prior SSE
            return chunk, nil, nil
        end

        --  strip leading "data: " (if present)
        local event_json = ss_event
        if ss_event:sub(1, 6) == "data: " then
            event_json = ss_event:sub(7)
        end
        local success, parsed = pcall(vim.json.decode, event_json)

        if success and parsed and parsed.choices and parsed.choices[1] then
            local first_choice = parsed.choices[1]
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
            chunk = (chunk or "") .. choice_text(first_choice)
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    return chunk, finish_reason, tool_calls
end

-- PRN does vllm have both finish_reason and stop_reason?
--   wait to handle it until actually needed
--   probably coalesce finish_reason|stop_reason to keep it transparent

return M
