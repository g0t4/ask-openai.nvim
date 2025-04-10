-- aka "legacy" completions endpoint
-- no chat history concept
--   good for single turn requests
--   can easily be used for back and forth if you are summarizing previous messages into the next prompt
-- raw prompt typically is reason to use this
--   i.e. FIM
--       TODO port my FIM to use this too, great way to test it and ensure its flexible
-- can get confusing if not "raw" and the backend applies templates that are shipped w/ the model...
--   you can use that just make sure you understand it and appropriately build the request body

local M = {}
local log = require("ask-openai.prediction.logger").predictions()
_G.PLAIN_FIND = true

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

function M.curl_for(body, base_url, frontend)
    local url_path = "/v1/completions"
    local url = base_url .. url_path
    return reusable_curl_seam(body, url, frontend)
end

function reusable_curl_seam(body, url, frontend)
    local request = {}

    body.stream = true
    local json = vim.fn.json_encode(body)

    -- TODO look for "curl" and "--no-buffer" to find all spots to merge together into this final backend
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

    -- TODO fix... by having the frontend do this, it is not the backends job to track which requests to abort
    --   this was when I only envisioned one request at a time but now with agents I could run them in parallel and why not with parallel capacity just sitting there on my GPUs
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

    -- FYI use nil to indicate nothing in the SSE... vs empty line which is a valid thingy right?
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
            -- ollama /api/generate doesn't prefix each SSE with 'data: '
            event_json = ss_event:sub(7)
        end
        local success, parsed = pcall(vim.json.decode, event_json)

        -- *** examples /api/generate:
        --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.1915236Z","response":"\n","done":false}
        --  done example:
        --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.2800621Z","response":"","done":true,"done_reason":"stop","total_duration":131193100,"load_duration":16550700,"prompt_eval_count":19,"prompt_eval_duration":5000000,"eval_count":12,"eval_duration":106000000}

        -- *** vllm /v1/completions responses:
        --  middle completion:
        --   {"id":"cmpl-eec6b2c11daf423282bbc9b64acc8144","object":"text_completion","created":1741824039,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":"ob","logprobs":null,"finish_reason":null,"stop_reason":null}],"usage":null}
        --
        --  final completion:
        --   {"id":"cmpl-06be557c45c24e458ea2e36d436faf60","object":"text_completion","created":1741823318,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":" and","logprobs":null,"finish_reason":"length","stop_reason":null}],"usage":null}
        --    pretty print with vim:
        --    :Dump(vim.json.decode('{"id":"cmpl-06be557c45c24e458ea2e36d436faf60","object":"text_completion","created":1741823318,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":" and","logprobs":null,"finish_reason":"length","stop_reason":null}],"usage":null}')
        -- {
        --   choices = { {
        --       finish_reason = "length",
        --       index = 0,
        --       logprobs = vim.NIL,
        --       stop_reason = vim.NIL,
        --       text = " and"
        --     } },
        --   created = 1741823318,
        --   id = "cmpl-06be557c45c24e458ea2e36d436faf60",
        --   model = "Qwen/Qwen2.5-Coder-3B",
        --   object = "text_completion",
        --   usage = vim.NIL
        -- }

        -- log:info("success:", success)
        -- log:info("choices:", vim.inspect(parsed))
        -- log:info("choices:", vim.inspect(parsed.choices))
        if success and parsed and parsed.choices and parsed.choices[1] then
            local first_choice = parsed.choices[1]
            finish_reason = first_choice.finish_reason
            if finish_reason ~= nil and finish_reason ~= vim.NIL then
                log:info("finsh_reason: ", finish_reason)
                done = true
                if finish_reason ~= "stop" and finish_reason ~= "length" then
                    log:warn("WARN - unexpected finish_reason: ", finish_reason, " do you need to handle this too?")
                end
            end
            if first_choice.text == nil then
                log:warn("WARN - unexpected, no choice in completion, do you need to add special logic to handle this?")
            else
                chunk = (chunk or "") .. first_choice.text
            end
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    -- TODO test passing back finish_reason (i.e. for an empty prediction log entry)
    return chunk, done, finish_reason
end

return M
