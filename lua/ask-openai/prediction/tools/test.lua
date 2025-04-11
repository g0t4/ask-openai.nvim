local uv = vim.loop


-- TODO do a test of fetch too... maybe even cooler!
-- --         "fetch": {
--         "command": "uvx",
--         "args": [
--             "--directory",
--             "/Users/wesdemos/repos/github/g0t4/mcp-servers/src/fetch",
--             "mcp-server-fetch",
--             "--ignore-robots-txt"
--         ]
--     },


-- MCP docs:
--   spec: https://modelcontextprotocol.io/specification/2025-03-26
--   message formats: https://modelcontextprotocol.io/specification/2025-03-26/basic#messages
--     requests: https://modelcontextprotocol.io/specification/2025-03-26/basic#requests
--     responses: https://modelcontextprotocol.io/specification/2025-03-26/basic#responses
--   schema: https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2025-03-26/schema.json
--
-- requests:
-- {
--   jsonrpc: "2.0";
--   id: string | number;
--   method: string;
--   params?: {
--     [key: string]: unknown;
--   };
-- }


function start_mcp_server(on_message)
    local stdin = uv.new_pipe(false)
    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    local options = {
        command = "npx",
        args = {
            "/Users/wesdemos/repos/github/g0t4/mcp-server-commands/build/index.js",
            "--verbose",
        },
    }

    local handle

    function on_exit(code, signal)
        print("MCP exited with code", code, "and signal", signal)
    end

    handle, pid = uv.spawn(options.command, {
        args = options.args,
        stdio = { stdin, stdout, stderr },
    }, on_exit)

    function on_stdout(err, data)
        print("MCP stdout:", data)
        assert(not err, err)
        -- receive messages

        if not data then
            return
        end

        for line in data:gmatch("[^\r\n]+") do
            local ok, msg = pcall(vim.json.decode, line)
            if ok and on_message then
                on_message(msg)
            else
                print("MCP decode error:", line)
                -- vim.notify("MCP decode error: " .. line, vim.log.levels.ERROR)
            end
        end
    end

    uv.read_start(stdout, on_stdout)

    function on_stderr(err, data)
        if err then
            print("MCP stderr error:", err)
            return
        end
        print("MCP stderr:", data)
    end

    uv.read_start(stderr, on_stderr)

    local function send(str)
        -- local str = vim.json.encode(msg) .. "\n"
        print("MCP send:", str)
        -- { "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {} }
        stdin:write(str .. "\n")
    end

    return {
        send = send,
        stop = function()
            -- handle:kill("sigterm")
            uv.shutdown(stdin, function()
                -- print("stdin shutdown", stdin)
                uv.close(handle, function()
                    -- free memory by closing handle
                    -- print("process closed", handle, pid)
                end)
            end)
        end
    }
end

local mcp = start_mcp_server(function(msg)
    print("MCP message:", vim.inspect(msg))
end)

local M = {}

M.setup = function()
    M.list_tools_test()
end

M.list_tools_test = function()
    print('test')
    -- local request_list_tools = {
    --     jsonrpc = "2.0",
    --     id = "1",
    --     method = "tools/list",
    --     params = {},
    -- }
    -- mcp.send(request_list_tools)
    -- { "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {} }
    mcp.send('{ "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {} }')
end

return M
