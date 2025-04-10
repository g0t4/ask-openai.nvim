local backend = require("ask-openai.backends.oai_chat_completions")
local log = require("ask-openai.prediction.logger").predictions() -- TODO rename to just ask-openai logger in general
local uv = vim.uv


-- FYI this may not live long, just a temp spot to split a seam between this and the frontend
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
end

function M.curl_for(json, base_url, frontend)
    -- PRN swap out backend if any non-standard quirks with a given API's handling, this s/b independent of the front end!
    -- PRN add more frontend handlers as needed (i.e. on request abort)
    --   in fact, attach front end to the request too and then frontend behavior like abort above can callback to the FE as needed
    local request = {}

    local options = {
        command = "curl",
        args = {
            "-fsSL",
            "--no-buffer", --i w/o this it batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
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
                local chunk, generation_done, done_reason = backend.process_sse(data)
                if chunk then
                    frontend.add_to_response_window(chunk)
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

return M
