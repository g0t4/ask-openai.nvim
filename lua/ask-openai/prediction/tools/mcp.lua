local uv = vim.loop

local M = {}

M.counter = 1
M.callbacks = {}


local servers = {
    -- fetch = {
    --     command = "uvx",
    --     args = {
    --         -- "--directory",
    --         -- "/Users/wesdemos/repos/github/g0t4/mcp-servers/src/fetch",
    --         "mcp-server-fetch",
    --         -- "--ignore-robots-txt",
    --     },
    -- },
    commands = {
        command = "npx",
        args = {
            "/Users/wesdemos/repos/github/g0t4/mcp-server-commands/build/index.js",
            -- "--verbose",
        },
    },
}


function start_mcp_server(name, on_message)
    local stdin = uv.new_pipe(false)
    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    local options = servers[name]

    local handle

    function on_exit(code, signal)
        print("MCP exited with code", code, "and signal", signal)
    end

    handle, pid = uv.spawn(options.command, {
        args = options.args,
        stdio = { stdin, stdout, stderr },
    }, on_exit)

    function on_stdout(err, data)
        -- print("MCP stdout:", data)
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
        end
        print("MCP stderr:", data)
    end

    uv.read_start(stderr, on_stderr)

    local function send(msg, callback)
        local this_id = tostring(M.counter) -- rather have them be strings, so we don't have array index issues
        msg.id = this_id
        msg.jsonrpc = "2.0"
        M.counter = M.counter + 1
        if callback then
            M.callbacks[this_id] = callback
        end
        local str = vim.json.encode(msg)
        -- print("MCP send:", str)
        stdin:write(str .. "\n")
    end

    local function tools_list(callback)
        send({ method = "tools/list" }, callback)
    end

    local function tools_call(tool_name, args, callback)
        send({
            method = "tools/call",
            params = {
                name = name,
                arguments = args,
            },
        }, callback)
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
        end,
        tools_list = tools_list,
        tools_call = tools_call,
    }
end

M.running_servers = {}

for name, server in pairs(servers) do
    print("starting mcp server " .. name)
    local mcp = start_mcp_server(name, function(msg)
        if msg.id then
            local callback = M.callbacks[msg.id]
            if callback then
                callback(msg)
            end
        end
        -- print("MCP message:", vim.inspect(msg))
    end)
    M.running_servers[name] = mcp
    mcp.tools_list(function(msg)
        -- print("tools/list:", vim.inspect(msg))
        for _, tool in ipairs(msg.result.tools) do
            print("found " .. tool.name)
            M.tools_available[tool.name] = tool
        end
    end)
end

M.tools_available = {}

M.setup = function()
    vim.api.nvim_create_user_command("McpListTools", function()
        print(vim.inspect(M.tools_available))
    end, { nargs = 0 })
end

return M
