local uv = vim.loop

local M = {}

M.counter = 1
M.callbacks = {}


local servers = {

    -- fetch is currently broken, hangs indefinitely or at least crashes when you try to send a message over STDIN at CLI
    --    but, dammit the inspector tool has it working with uvx :(
    --    it does this on me when I use it manually or using uv.spawn below... smth isn't right
    --
    --         |     raise RuntimeError(
    --         |         "Received request before initialization was complete"
    --         |     )   --
    --
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
    -- print("starting mcp server " .. name)
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
            -- print("found " .. tool.name)
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

function M.openai_tools()
    local tools = {}
    for _, mcp_tool in pairs(M.tools_available) do
        table.insert(tools, openai_tool(mcp_tool))
    end
    return tools
end

function openai_tool(mcp_tool)
    -- OpenAI docs for tools: https://platform.openai.com/docs/api-reference/chat/create#chat-create-tools

    -- effectively a deep clone
    params = {}
    params.required = mcp_tool.inputSchema.required
    params.type = mcp_tool.inputSchema.type
    params.properties = {}
    for k, v in pairs(mcp_tool.inputSchema.properties) do
        params.properties[k] = {}
        for k2, v2 in pairs(v) do
            params.properties[k][k2] = v2
        end
        params.properties[k] = v
    end

    -- yay qwen responded:
    -- [3.977]sec [TRACE] on_stdout chunk:  data: {"id":"chatcmpl-184","object":"chat.completion.chunk","created":1744438704,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"tool_calls"}]}
    return {
        type = "function",
        ["function"] = {
            name = mcp_tool.name,
            -- FYI mcp-server-commands doesn't currently set a desc (won't see that in testing)
            description = mcp_tool.description,
            parameters = params,
            -- strict = false -- default is false... should I set true?
        }
    }
end

return M
