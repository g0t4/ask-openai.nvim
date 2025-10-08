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

