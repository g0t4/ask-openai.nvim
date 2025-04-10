local M = {}
local log = require("ask-openai.prediction.logger").predictions()
local uv = vim.uv

-- docs:
-- /chat/completions: https://docs.vllm.ai/en/stable/serving/openai_compatible_server.html#chat-api

-- FYI this is intended for use w/ instruct models
--  TODO! determine if this can be generalized...
--  TODO TEST THIS WITH VLLM's /chat/completions
--  TODO test with OpenAI too
-- TESTED WITH:
--  ollama



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
end

function M.curl_for(json, base_url, frontend)
    local request = {}

    -- TODO look for "curl" and "--no-buffer" to find all spots to merge together into this final backend
    local options = {
        command = "curl",
        args = {
            "-fsSL",
            "--no-buffer", -- w/o this curl batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            base_url .. "/v1/chat/completions",
            "-H", "Content-Type: application/json",
            "-d", json
        },
    }

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    options.on_exit = function(code, signal)
        if code ~= 0 then
            log:error("spawn - non-zero exit code:", code, "Signal:", signal)
        end
        stdout:close()
        stderr:close()

        -- this shoudl be attacked to a specific request (not any module)
        -- clear out refs
        request.handle = nil
        request.pid = nil
    end

    M.terminate()

    request.handle, request.pid = uv.spawn(options.command, {
        args = options.args,
        stdio = { nil, stdout, stderr },
    }, options.on_exit)

    options.on_stdout = function(err, data)
        -- log:trace("on_stdout chunk: ", data)
        if err then
            log:warn("on_stdout error: ", err)
            return
        end
        if data then
            vim.schedule(function()
                local chunk, generation_done, done_reason = M.sse_to_chunk(data)
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
    end
    uv.read_start(stdout, options.on_stdout)

    options.on_stderr = function(err, data)
        log:warn("on_stderr chunk: ", data)
        if err then
            log:warn("on_stderr error: ", err)
        end
        -- TODO frontend.handle_error()?
    end
    uv.read_start(stderr, options.on_stderr)

    return request
end

function M.sse_to_chunk(data)
    -- SSE = Server-Sent Event
    -- split on lines first (each SSE can have 0+ "event" - one per line)

    local chunk = nil -- combine all chunks into one string and check for done
    local done = false
    local finish_reason = nil
    for ss_event in data:gmatch("[^\r\n]+") do
        if ss_event:match("^data:%s*%[DONE%]$") then
            -- done, courtesy last event... mostly ignore b/c finish_reason already comes on the prior SSE
            return chunk, true
        end

        --  strip leading "data: " (if present)
        local event_json = ss_event
        if ss_event:sub(1, 6) == "data: " then
            event_json = ss_event:sub(7)
        end
        local success, parsed = pcall(vim.json.decode, event_json)

        -- *** examples /v1/chat/completions
        -- {"id":"chatcmpl-209","object":"chat.completion.chunk","created":1743021818,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"."},"finish_reason":null}]}
        -- {
        --   "id": "chatcmpl-209",
        --   "object": "chat.completion.chunk",
        --   "created": 1743021818,
        --   "model": "qwen2.5-coder:7b-instruct-q8_0",
        --   "system_fingerprint": "fp_ollama",
        --   "choices": [
        --     {
        --       "index": 0,
        --       "delta": {
        --         "role": "assistant",
        --         "content": "."
        --       },
        --       "finish_reason": null
        --     }
        --   ]
        -- }
        -- {"id":"chatcmpl-209","object":"chat.completion.chunk","created":1743021818,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"stop"}]}
        if success and parsed and parsed.choices and parsed.choices[1] then
            local choice = parsed.choices[1]
            finish_reason = choice.finish_reason
            if finish_reason ~= nil and finish_reason ~= vim.NIL then
                done = true
                if finish_reason ~= "stop" and finish_reason ~= "length" then
                    log:warn("WARN - unexpected /v1/chat/completions finish_reason: ", finish_reason, " do you need to handle this too?")
                end
            end
            if choice.delta == nil or choice.delta.content == nil then
                log:warn("WARN - unexpected, no delta.content in completion choice, do you need to add special logic to handle this?")
            end
            chunk = (chunk or "") .. choice.delta.content
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    -- TODO test passing back finish_reason (i.e. for an empty response though that shouldn't happen when asking a question)
    return chunk, done, finish_reason
end

return M
