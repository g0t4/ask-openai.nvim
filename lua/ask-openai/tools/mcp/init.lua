local log = require("ask-openai.logs.logger").predictions()
local ansi = require("ask-openai.predictions.ansi")
local plumbing = require("ask-openai.tools.plumbing")
local safely = require("ask-openai.helpers.safely")

local uv = vim.uv

local M = {}

-- TODO! look into Memory tools / RAG, i.e. in Qwen-Agent
-- TODO! https://github.com/QwenLM/Qwen-Agent/blob/main/qwen_agent/memory/memory.py
-- also check out other examples in qwen-agent for new ideas:
--    https://github.com/QwenLM/Qwen-Agent/tree/main/examples
-- PRN also I wanna test out large qwen models, hosted by Alibaba/groq/others

local servers = {

    -- PRN implement https://agentskills.io/mcp https based MCP tools... is it a websocket?

    fetch = {
        -- PRN only include this tool if initial request includes /web?

        -- -- * via docker
        -- command = "docker",
        -- args = { "run", "-i", "--rm", "weshigbee/mcp-fetch" },
        -- mcp/fetch image is prebuilt but has robots.txt and user-agent crap that slows things down
        -- FYI server response logs:
        --   docker container logs foo_bar --follow | jq
        --   docker container logs jovial_blackburn --follow | jq --compact-output

        -- -- * via source
        transport = "stdio",
        command = "uvx",
        args = {
            "--directory",
            os.getenv("HOME") .. "/repos/github/g0t4/mcp-servers/src/fetch",
            "mcp-server-fetch",
            "--ignore-robots-txt", -- DO NOT WASTE TIME QUERYING robots.txt... YIKES (s/b default off IMO) ... if I can presonally browse to a website, my AI assistant can do it for me too
        },
    },
    commands = {
        transport = "stdio",
        command = "npx",
        args = {
            os.getenv("HOME") .. "/repos/github/g0t4/mcp-server-commands/build/index.js",
            -- FYI leave --verbose on for now given I am using a log file so it s/b NBD
            --    this will be a huge help in troubleshooting hung tool calls and other issues
            "--verbose",
        },
    },
}

function start_mcp_server_stdio(name)
    local options = servers[name]
    local server_log_name = "[" .. name:upper() .. "]"

    local handle, pid

    local function on_exit(code, signal)
        log:trace_on_exit_errors(code, signal) -- FYI switch _errors/_always

        handle:close()

        if vim.v.exiting ~= nil then
            local msg = string.format("MCP server %s EXITED\n\n  *NOTE: vim is not shutting down*\n\nRESTART NEOVIM if you need the server running", server_log_name)
            log:error(ansi.white_bold(ansi.red_bg(msg)))
            vim.notify(msg, vim.log.levels.WARN)
        else
            -- I never see this log entry on shutdown...
            -- reminds me => perhaps I need to actually trigger exit of server too?
            --   but, I've never seen leaked MCP server process... doesn't mean it never happens!
            log:error(string.format("MCP server %s exited (during neovim shutdown)", server_log_name))
        end
    end

    local stdin = uv.new_pipe(false)
    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)
    handle, pid = uv.spawn(options.command,
        ---@diagnostic disable-next-line: missing-fields
        {
            args = options.args,
            stdio = { stdin, stdout, stderr },
        },
        on_exit)

    -- Server‑specific state. Each server gets its own request ID counter and pending callbacks.
    local counter = 1
    local callbacks = {}

    local function on_server_response_generic(server_response)
        -- Response object (success or failure)
        -- - Server does NOT send response to notifications
        -- - https://www.jsonrpc.org/specification#response_object
        --   - ID of request is required
        --   - Either `error` or `result` is required
        --     - NOT BOTH
        --     - `result` object not constrained by spec
        --     - `error` object has code/message/data properties: https://www.jsonrpc.org/specification#error_object
        if server_response.error then
            log:error(string.format("MCP %s error response:", server_log_name), server_response.error)
        end

        -- log:info("MCP response:", vim.inspect(server_response))
        local id = server_response.id
        if id then
            local callback = callbacks[id]
            if callback then
                -- PRN strip out errors?
                --   not sure I really ever use error right now!
                --   PRN find out if/how I should be using JSONRPC error objects? (look at other MCP servers, try with fetch an invalid URL?)
                --   IOTW only pass result? => callback(server_response.result)
                callback(server_response)
                callbacks[id] = nil
            end
        end
    end

    local pending_json = ""
    local function on_stdout(read_error, data)
        log:log_if_stdio_read_error(string.format("MCP on_stdout %s", server_log_name), read_error, data) -- FYI switch _errors/_always with:    log:trace_stdio_read_always("MCP ...
        if data == nil then return end -- EOF

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

            local ok, response = safely.decode_json(line)
            if ok then
                on_server_response_generic(response)
            else
                log:error(string.format("MCP STDOUT decode error %s OK:", server_log_name), ok)
                log:error(string.format("MCP STDOUT decode error %s LINE:", server_log_name), line)
                log:error(string.format("MCP STDOUT decode error %s MSG:", server_log_name), vim.inspect(response))
            end
        end

        -- *** DO NOT attempt to decode/dispatch before \n arrives
    end


    uv.read_start(stdout, on_stdout)

    local function on_stderr(read_error, data)
        log:log_if_stdio_read_error(string.format("MCP on_stderr %s", server_log_name), read_error, data) -- FYI switch _errors/_always with:    log:trace_stdio_read_always("MCP ...
        if data == nil then return end -- EOF -- * add this line if add logic below

        -- IIRC this rarely ever happens and would be transport specific.
        --   keep in mind if a tool call fails, the result comes through on_stdout and simply has isError=true
        log:error(string.format("MCP %s STDERR:", server_log_name), ansi.red(data))
    end

    uv.read_start(stderr, on_stderr)

    local function send_stdio(request)
        local json = vim.json.encode(request)
        -- log:info(string.format("MCP write %s:", server_log_name), json)
        stdin:write(json .. "\n")
    end

    local function send_generic(request, callback)
        -- Regular request (with optional callback). ID is always set unless caller explicitly provides one.
        if not request.id then
            request.id = counter
            counter = counter + 1
        end
        request.jsonrpc = "2.0"

        if callback then
            callbacks[request.id] = callback
        end
        send_stdio(request)
    end

    --- Send a JSON-RPC notification
    ---@param request { method: string, params?: any, [any]: any }
    local function notify_generic(request)
        -- * notifications CANNOT have ID: https://www.jsonrpc.org/specification#notification
        -- BTW notification is a type of request
        -- modelcontextprotocol uses "notifications/" method prefix, i.e.: notifications/initialized and notifications/tools/list_changed
        request.jsonrpc = "2.0"
        send_stdio(request)
    end

    local function tools_list(callback)
        send_generic({ method = "tools/list" }, callback)
    end

    local function tools_call(id, tool_name, args, callback)
        -- PRN/TODO btw your downstream code uses result object for almost everything, even tool call failures... that is probably fine but I should find out if a failed tool call is suppose to be presented as an error object on the response or as-is with result.isError etc?
        send_generic({
            id = id,
            method = "tools/call",
            params = {
                name = tool_name,
                arguments = args,
            },
        }, callback)
    end

    -- Perform initialization before requesting the tool list.
    -- This logic was previously in the outer for‑loop; moving it here keeps the
    -- server lifecycle self‑contained.
    local client_init_params = {
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
            version = "", -- version required (error if missing)... COMMENT THIS OUT TO TEST ERROR HANDLING!
        },
    }

    send_generic({ method = "initialize", params = client_init_params }, function(server_init)
        log:trace(string.format("MCP initialize response %s:", server_log_name), vim.inspect(server_init))

        -- * abort on init failure
        if server_init.error then
            local err = server_init.error
            local msg = ""
            if type(err) == "table" and err.message ~= nil then
                -- log them embedded error.message if available
                msg = string.format("MCP initialize error (SEE PATH below) %s: %s", server_log_name, err.message)
                -- FYI message is a JSON string, so I would have to deserialize it to read .path... that's not necessary! I can just read the JSON when I have a failure!
            else
                msg = string.format("MCP initialize error %s (no message)", server_log_name)
            end
            log:error(msg)
            vim.notify(msg, vim.log.levels.ERROR)
            return
        end

        -- fetch MCP server rejects this (and on_exit's from neovim uv runner... but when I run uvx directly and paste in messages it keeps working after failure for notifications/initialized... interesting), works fine w/o this:
        --  - COMMANDS MCP it doesn't matter if I send this or don't send this
        --  - ok the issue might be that notifications don't include an ID? => YUP fetch works without the ID on the notification!
        --  - docs: https://modelcontextprotocol.io/specification/2024-11-05/basic/lifecycle#initialization
        notify_generic({ method = "notifications/initialized" })

        -- PRN do I need to wait before tools/list ? IIUC notifications/initialized doesn't get a server response... so in this case, I am not waiting to send tools/list:
        tools_list(function(response)
            if response.error then
                log:error(string.format("tools/list@%s error:", server_log_name), vim.inspect(response))
                return
            end
            for _, tool in ipairs(response.result.tools) do
                tool.call = tools_call
                M.tools_available[tool.name] = tool
            end
        end)
    end)

    local function stop()
        -- handle:kill("sigterm")
        uv.shutdown(stdin, function()
            uv.close(handle, function()
                -- free memory by closing handle
            end)
        end)
    end

    return { stop = stop }
end

M.running_servers = {}
M.tools_available = {}

for name, server in pairs(servers) do
    local server_log_name = "[" .. name:upper() .. "]"
    -- log:trace("starting mcp server " .. name)

    local mcp = start_mcp_server_stdio(name)
    M.running_servers[name] = mcp
end


function M.setup()
    vim.api.nvim_create_user_command("McpLogToolsList", function()
        local message = vim.inspect(M.tools_available)
        log:info(message)
        print(message)
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

    tool.call(tool_call.id, name, args_decoded, vim.schedule_wrap(callback))
end

M._cached_run_process_instructions = nil
---@param tool_name string
---@return string|nil instructions (if applicable for tool_name)
function M.get_system_message_instructions(tool_name)
    -- Return system message instructions for specific MCP tools.
    if tool_name == "run_process" then
        if M._cached_run_process_instructions then
            return M._cached_run_process_instructions
        end

        local files = require("ask-openai.helpers.files")
        local run_process_dir = "~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/tools/mcp/run_process"
        local commits = files.read_text(run_process_dir .. "/commits.md"):gsub("<<COAUTHOR_NAME>>", "gptoss120b")
        local commands = files.read_text(run_process_dir .. "/commands.md")
        M._cached_run_process_instructions = commits .. "\n\n" .. commands
        return M._cached_run_process_instructions
    end

    if tool_name == "fetch" then
        if M._cached_fetch_instructions then
            return M._cached_fetch_instructions
        end
        local files = require("ask-openai.helpers.files")
        local fetch_path = "~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/tools/mcp/fetch/fetch.md"
        M._cached_fetch_instructions = files.read_text(fetch_path)
        return M._cached_fetch_instructions

        -- TODO fetch tool/instruction improvement ideas
        -- ** setup a subagent for each request w/ a question/statement about what is of interest, let it gather multiple links and report back with links and what matters about each one
        --    subagent can have detailed instructions (/INSTRUCT like) for GitHub links and many other common sites to make a more productive experience fetching from common sites
        --    also means instructions don't have to polluate normal system prompt for top level agent trace
    end

    return nil
end

return M
