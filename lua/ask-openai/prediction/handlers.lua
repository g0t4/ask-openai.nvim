local uv = vim.uv
local M = {}

local once = false
function M.ask_for_prediction()
    print("Asking for prediction...")
    -- do return end
    M.reject() -- always cancel last prediction before starting a new one :)

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
            vim.schedule(function()
                local original_row, original_col = unpack(vim.api.nvim_win_get_cursor(0))
                local line = vim.api.nvim_buf_get_lines(0, original_row - 1, original_row, false)[1]
                local before = line:sub(1, original_col)
                local after = line:sub(original_col + 1)
                local first_data_line_only = data:match("^(.-)\n")
                local new_line_with_data_at_cursor = before .. first_data_line_only .. after
                -- vim.o.eventignore = "all"
                print("after set eventignore")
                -- CRAP what if data has new lines :)... no problem to insert it... lets just insert contents of first row for testing
                once = true
                vim.cmd("noautocmd lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'Line 1', 'Line 2'})")
                -- vim.cmd("noautocmd lua vim.api.nvim_buf_set_lines(0," .. tostring(original_row - 1) .. ", " ..
                --     tostring(original_row) .. ", false, { '" .. new_line_with_data_at_cursor .. "' })")

                print("after insert")
                -- TODO disable events CursorMovedI temporarily instead of hack bool M.disable_cursor_move_detect
                -- vim.api.nvim_win_set_cursor(0, { original_row, original_col + #first_data_line_only })
                print("after insert/move")
                -- is cursor move synchronous? or do I need to use a callback?
                -- vim.o.eventignore = ""
                print('after clear eventignore')
            end)
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
        -- TODO what if kill fails? how do I mark this prediction as discard it?
        --   or before it terminates, if another chunk arrives... I should track a request_id (guid) and use that to ignore if data still arrives after I request termination
        --   and before it terminates I start another request... which I want for responsiveness
        --
        M.handle = nil
        M.pid = nil
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
