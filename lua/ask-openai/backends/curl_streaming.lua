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

    options.on_stdout = function(err, data)
        log:trace("on_stdout chunk: ", data)
        if err then
            log:warn("on_stdout error: ", err)
            return
        end
        if not data then
            return
        end
        vim.schedule(function()
            local chunk, generation_done, done_reason = M.sse_to_chunk(data, choice_text)
            if chunk then
                frontend.process_chunk(chunk)
            end
            -- PRN anything on done?
            -- if generation_done then
            --     PRN add for empty response checking like with predictions (need to capture all chunks to determine this and its gonna be basically impossible to have the response be valid and empty, so not a priority)
            --     this_prediction:mark_generation_finished()
            -- end
        end)
    end
    uv.read_start(stdout, options.on_stdout)

    options.on_stderr = function(err, data)
        if data ~= nil and data ~= "" then
            -- legit errors, i.e. from curl, will show as text in data
            log:warn("on_stderr data: ", data)
            print("on_stderr data: ", data)
            frontend.on_stderr_data(data)
        end
        if err then
            log:warn("on_stderr ", err)
            -- lets print for now too and see how many false positives we get
            print("on_stderr: ", err)
        end
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
