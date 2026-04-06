local log = require("ask-openai.logs.logger").predictions()
local ansi = require("ask-openai.predictions.ansi")
local plumbing = require("ask-openai.tools.plumbing")
local safely = require("ask-openai.helpers.safely")

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

    -- * TODO need to send initialize for fetch to work (optional on mcp-server-commands below)
    -- -- fetch via docker container:
    fetch = {
        command = "docker",
        args = { "run", "-i", "--rm", "mcp/fetch" },
    },
    --
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
            -- FYI leave --verbose on for now given I am using a log file so it s/b NBD
            --    this will be a huge help in troubleshooting hung tool calls and other issues
            "--verbose",
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
        log:info(ansi.white_bold(ansi.red_bg(string.format("MCP SERVER '%s' EXITED... DO YOU NEED TO RESTART IT? (ok to ignore this error if nvim is exiting)", name))))
    end

    handle, pid = uv.spawn(options.command,
        ---@diagnostic disable-next-line: missing-fields
        {
            args = options.args,
            stdio = { stdin, stdout, stderr },
        },
        on_exit)

    local pending_json = ""

    local function on_stdout(read_error, data)
        log:log_if_stdio_read_error(string.format("MCP on_stdout [%s]", name), read_error, data) -- FYI switch _errors/_always
        -- log:trace_stdio_read_always("MCP on_stdout", read_error, data)
        if data == nil then return end -- EOF

        -- TODO ignore / loosely validate initialize response

        pending_json = pending_json .. data

        -- PRN/TODO support content-length "header" before message? right now my MCP server mcp-server-commands (typescript MCP SDK) doesn't include content-length style (NOT AFAICT, maybe a setting to enable?)
        --   instead, right now responses are delimited by a trailing \n
        -- TODO add integration tests to make sure this is solid
        -- TODO you do not want tool calling to randomly fail for plumbing reasons!!!
        -- TODO look at what you did with SSEs in streaming callbacks via uv.spawn and curl... can be similar integration test style here
        --  NOTE not using curl implementation of loop/SSE/etc b/c SSE convention is \n\n unlike here where message is one trailing \n
        while true do
            -- FYI could be multiple responses/notifications (aka messages) in one callback, hence loop
            local line, rest = pending_json:match("^(.-)\r?\n(.*)$")
            if not line then break end
            pending_json = rest

            local ok, msg = safely.decode_json(line)
            if ok and on_message then
                on_message(msg)
            else
                log:info(string.format("MCP decode error [%s]:", name), line)
            end
        end

        -- *** DO NOT attempt to decode/dispatch before \n arrives
    end


    uv.read_start(stdout, on_stdout)

    local function on_stderr(read_error, data)
        log:log_if_stdio_read_error("MCP on_stderr", read_error, data) -- FYI switch _errors/_always
        -- log:trace_stdio_read_always("MCP on_stderr", read_error, data)
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
        local msg_json = vim.json.encode(msg)
        log:info(string.format("MCP send [%s]:", name), msg_json)
        stdin:write(msg_json .. "\n")
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

    -- Perform initialization before requesting the tool list.
    local init_params = {
        -- go with oldest protocolVersion for now, even though I am using @modelcontextprotocol/sdk v1.9.0 which was released in April 2025 which would put it after the protocolVersion==2025-03-26
        protocolVersion = "2024-11-05",
        capabilities = {
            roots = { listChanged = false },
            -- WARNING: empty table {} => maps to an empty JSON array:
            -- sampling = {}, -- serializes as empty JSON array (this triggers error response)
            -- sampling = vim.empty_dict(), -- use this to serialize an empty JSON object (this succeeds)
        },
        clientInfo = {
            name = "ask-openai",
            -- version = "", -- version required (error if missing)
        },
    }

    mcp.send({ method = "initialize", params = init_params }, function(init_msg)
        log:info(string.format("MCP initialize response [%s]:", name), vim.inspect(init_msg))

        -- * abort on init failure
        if init_msg.error then
            local err = init_msg.error
            local msg = ""
            if type(err) == "table" and err.message ~= nil then
                -- log them embedded error.message if available
                msg = string.format("MCP initialize error (SEE PATH below) [%s]: %s", name, err.message)
                -- FYI message is a JSON string, so I would have to deserialize it to read .path... that's not necessary! I can just read the JSON when I have a failure!
            else
                msg = string.format("MCP initialize error [%s] (no message)", name)
            end
            log:error(msg)
            vim.notify(msg, vim.log.levels.ERROR)

            return
        end

        mcp.send({ method = "notifications/initialized" })

        -- PRN do I need to wait before tools/list ? IIUC notifications/initialized doesn't get a server response... so in this case, I am not waiting to send tools/list:
        mcp.tools_list(function(msg)
            if msg.error then
                log:error("tools/list@" .. name .. " error:", vim.inspect(msg))
                return
            end
            for _, tool in ipairs(msg.result.tools) do
                tool.server = mcp
                M.tools_available[tool.name] = tool
            end
        end)
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
        callback(plumbing.create_tool_call_output_for_error_message("Invalid MCP tool name: " .. name))
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

M._cached_run_process_instructions = nil
---@param tool_name string
---@return string|nil instructions (if applicable for tool_name)
function M.get_system_message_instructions(tool_name)
    if tool_name ~= "run_process" then
        return nil
    end

    if M._cached_run_process_instructions then
        return M._cached_run_process_instructions
    end
    -- PRN could get these from a named MCP prompt resource?

    local files = require("ask-openai.helpers.files")

    local run_process_dir = "~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/tools/mcp/run_process"

    local commits = files.read_text(run_process_dir .. "/commits.md"):gsub("<<COAUTHOR_NAME>>", "gptoss120b")
    -- TODO where to get placeholder value(s)? (i.e COAUTHOR_NAME)

    local commands = files.read_text(run_process_dir .. "/commands.md")

    -- PRN have a checker that looks at blank lines at end/start of join sections then adds \n only if needed
    M._cached_run_process_instructions = commits .. "\n\n" .. commands

    return M._cached_run_process_instructions
end

return M
