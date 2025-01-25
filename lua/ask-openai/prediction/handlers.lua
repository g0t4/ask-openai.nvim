local uv = vim.uv
local M = {}

function M.ask_for_prediction()
    -- print("Asking for prediction...")

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)
    local command = "fish"
    local args = {
        "-c",
        "for i in (seq 1 10); echo $i; sleep 1; end"
        -- "echo foo && sleep 2 && echo bar",
    }

    M.handle, M.pid = uv.spawn(command, {
        args = args,
        stdio = { nil, stdout, stderr },
    }, function(code, signal)
        print("Exit code:", code, "Signal:", signal)
        stdout:close()
        stderr:close()
    end)
    print("handle", M.handle, M.pid)

    uv.read_start(stdout, function(err, data)
        assert(not err, err)
        if data then
            print("STDOUT:", data)
        end
    end)

    uv.read_start(stderr, function(err, data)
        assert(not err, err)
        if data then
            print("STDERR:", data)
        end
    end)
end

function M.reject()
    -- print("Rejecting prediction...")
    if M.handle and not M.handle:is_closing() then
        print("Terminating process...")
        M.handle:kill("sigterm") -- Send SIGTERM to the process
        M.handle:close()         -- Close the handle
    end
end

function M.accept_all()
    -- print("Accepting all predictions...")
end

function M.accept_line()
    -- print("Accepting line prediction...")
end

function M.accept_word()
    -- print("Accepting word prediction...")
end

return M
