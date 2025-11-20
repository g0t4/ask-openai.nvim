local log = require("ask-openai.logs.logger").predictions()
local ansi = require("ask-openai.prediction.ansi")
local uv = vim.uv

local M = {}

M.counter = 1
M.callbacks = {}

-- TODO! look into Memory tools / RAG, i.e. in Qwen-Agent
-- TODO! https://github.com/QwenLM/Qwen-Agent/blob/main/qwen_agent/memory/memory.py
-- also check out other examples in qwen-agent for new ideas:
--    https://github.com/QwenLM/Qwen-Agent/tree/main/examples
-- PRN also I wanna test out large qwen models, hosted by Alibaba/groq/others

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
            os.getenv("HOME") .. "/repos/github/g0t4/mcp-server-commands/build/index.js",
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

    local function on_exit(code, signal)
        log:trace_on_exit_errors(code, signal) -- FYI switch _errors/_always

        handle:close()

        -- TODO reopen?
        log:trace(ansi.white_bold(ansi.red_bg("MCP SERVER EXITED... DO YOU NEED TO RESTART IT? (ok to ignore this error if nvim is exiting)")))
    end

    handle, pid = uv.spawn(options.command,
        ---@diagnostic disable-next-line: missing-fields
        {
            args = options.args,
            stdio = { stdin, stdout, stderr },
        },
        on_exit)

    local function on_stdout(read_error, data)
        log:trace_stdio_read_errors("MCP on_stdout", read_error, data) -- FYI switch _errors/_always
        if data == nil then return end -- EOF

        for line in data:gmatch("[^\r\n]+") do
            local ok, msg = pcall(vim.json.decode, line)
            if ok and on_message then
                on_message(msg)
            else
                log:trace("MCP decode error:", line)
            end
        end
    end

    uv.read_start(stdout, on_stdout)

    local function on_stderr(read_error, data)
        log:trace_stdio_read_errors("MCP on_stderr", read_error, data) -- FYI switch _errors/_always
        -- if data == nil then return end -- EOF -- * add this line if add logic below
    end

    uv.read_start(stderr, on_stderr)

    local function send(msg, callback)
        if not msg.id then
            -- set a unique id if no id is provided
            msg.id = M.counter
            M.counter = M.counter + 1
        end
        msg.jsonrpc = "2.0"
        if callback then
            M.callbacks[msg.id] = callback
        end
        local str = vim.json.encode(msg)
        -- log:trace("MCP send:", str)
        stdin:write(str .. "\n")
    end

    local function tools_list(callback)
        send({ method = "tools/list" }, callback)
    end

    local function tools_call(id, tool_name, args, callback)
        send({
            id = id,
            method = "tools/call",
            params = {
                name = tool_name,
                arguments = args,
            },
        }, callback)
    end

    return {
        send = send,
        stop = function()
            -- handle:kill("sigterm")
            uv.shutdown(stdin, function()
                uv.close(handle, function()
                    -- free memory by closing handle
                end)
            end)
        end,
        tools_list = tools_list,
        tools_call = tools_call,
    }
end

M.running_servers = {}

for name, server in pairs(servers) do
    -- log:trace("starting mcp server " .. name)
    local mcp = start_mcp_server(name, function(msg)
        if msg.id then
            local callback = M.callbacks[msg.id]
            if callback then
                callback(msg)
            end
        end
        -- log:trace("MCP message:", vim.inspect(msg))
    end)
    M.running_servers[name] = mcp
    mcp.tools_list(function(msg)
        if msg.error then
            log:error("tools/list@" .. name .. " error:", vim.inspect(msg))
            return
        end
        -- log:luaify_trace("tools/list:", msg)
        for _, tool in ipairs(msg.result.tools) do
            -- log:trace("found " .. tool.name)
            tool.server = mcp
            M.tools_available[tool.name] = tool
        end
    end)
end

M.tools_available = {}

function M.setup()
    vim.api.nvim_create_user_command("McpLogToolsList", function()
        log:trace(vim.inspect(M.tools_available))
    end, { nargs = 0 })
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

---@param tool_name string
---@return boolean
function M.handles_tool(tool_name)
    local tool = M.tools_available[tool_name]
    return tool ~= nil
end

---@param tool_call table
---@param callback ToolCallDoneCallback
function M.send_tool_call(tool_call, callback)
    -- tool call: {
    --   ["function"] = {
    --     arguments = '{"command":"ls -la","cwd":""}',
    --     name = "run_command"
    --   },
    --   id = "call_8yoj8qqo",
    --   index = 0,
    --   type = "function"
    -- }

    local name = tool_call["function"].name
    local tool = M.tools_available[name]
    if tool == nil then
        log:error("requested tool not found: " .. name)
        vim.schedule_wrap(function()
            ---@type MCPToolCallOutputError
            local call_output = {
                error = { message = "invalid_tool_name: " .. name, }
            }
            callback(call_output)
        end)
        return
    end

    local args = tool_call["function"].arguments
    -- TODO ideally the caller would already transform json into lua tables
    -- TODO and have parsed XML instead of JSON if that is what a model responds with
    local args_decoded = vim.json.decode(args)
    -- log:trace("args_decoded: " .. vim.inspect(args_decoded))

    -- PRN timeout mechanism? might be a good spot to wrap an async timer to check back (wait for the need to arise)

    tool.server.tools_call(tool_call.id, name, args_decoded, vim.schedule_wrap(callback))
end

return M
