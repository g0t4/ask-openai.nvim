local log = require("devtools.logs.logger").universal()
local SSEDataOnlyParser = require("ask-openai.backends.sse.data_only_parser")
local ansi = require("devtools.ansi")
local plumbing = require("ask-openai.tools.plumbing")
local safely = require("ask-openai.helpers.safely")
local uv_spawn = require("ask-openai.helpers.uv_spawn")

local uv = vim.uv

local M = {}

-- TODO! look into Memory tools / RAG, i.e. in Qwen-Agent
-- TODO! https://github.com/QwenLM/Qwen-Agent/blob/main/qwen_agent/memory/memory.py
-- also check out other examples in qwen-agent for new ideas:
--    https://github.com/QwenLM/Qwen-Agent/tree/main/examples
-- PRN also I wanna test out large qwen models, hosted by Alibaba/groq/others

local servers = {

    -- PRN implement https://agentskills.io/mcp https based MCP tools... is it a websocket?

    fetch    = {
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
        command = "uv",
        args = {
            -- do not use uvx, that will install central/cached copy
            "run",
            "--directory",
            os.getenv("HOME") .. "/repos/github/g0t4/mcp-servers/src/fetch",
            "mcp-server-fetch",
        },
        -- env = { FOO = "BAR" }, -- example, env var overrides (BTW see below for env var inheritence + overrides logic + auto drop VIRTUAL_ENV* unless you set it in the overrides here
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
    agents   = {
        transport = "stdio",
        command = "uv",
        args = {
            "run",
            "--directory",
            os.getenv("HOME") .. "/repos/github/g0t4/mcp-servers/src/agents",
            "-m",
            "subagents",
            -- PRN add verbosity flag across all my tools "--verbose",
        },
    },
    -- FYI this works but I think I'll want the tools to be opt-in per first prompt... as there are many and basically just lets your agent modify scripts in tampermonkey which I can't help but think... can't I just do this with files in a dropbox folder and have them auto sync into TM?!
    -- tampermonkey = {
    --     transport = "stdio",
    --     command = "npx",
    --     args = {
    --         "-y",
    --         "tampermonkey-mcp@latest"
    --     }
    -- },
    --
    -- TODO I want a web browser "profile" I think... can be /my_browser or smth like that and then I also want it to add MCP devtools server!
    -- and consider adding this in claude code too, since I use claude for TM scripts lately
    -- npm install -g chrome-devtools-mcp@latest
    -- claude mcp add --transport stdio --scope project chrome-devtools-mcp -- npx -y chrome-devtools-mcp@latest --slim --no-usage-statistics --auto-connect --browser-url http://127.0.0.1:9222
    --

    -- TODO add these to specific repos using repo_root/.mcp.json file like langchain-ai/langchain repo has
    -- mcp_docs = {
    --     transport = "http",
    --     url = "https://modelcontextprotocol.io/mcp",
    -- }
    -- langchain_docs = {
    --     transport = "http",
    --     url = "https://docs.langchain.com/mcp",
    -- }
}

-- ============================================================================
-- MCPClient base class
-- ============================================================================

---@class MCPClient
---@field server_log_name string
---@field counter integer
---@field callbacks_by_request_id table<any, ToolCallDoneCallback>
---@field progress_callbacks_by_token table<any, ToolCallOnProgress>
local MCPClient = {}
MCPClient.__index = MCPClient

--- Dispatch a parsed JSON-RPC message (response or notification).
--- Both transports share this logic after parsing.
---@param self MCPClient
---@param message MCP_JSONRPCMessage
function MCPClient:dispatch_message(message)
    -- Response object (success or failure)
    -- - Server does NOT send response to notifications
    -- - https://www.jsonrpc.org/specification#response_object
    --   - ID of request is required
    --   - Either `error` or `result` is required
    --     - NOT BOTH
    --     - `result` object not constrained by spec
    --     - `error` object has code/message/data properties: https://www.jsonrpc.org/specification#error_object
    if message.error then
        log:error(string.format("MCP %s error response:", self.server_log_name), vim.inspect(message.error))
    end

    local request_id = message.id
    if request_id then
        local callback = self.callbacks_by_request_id[request_id]
        if callback then
            callback(message)
            self.callbacks_by_request_id[request_id] = nil
            self.progress_callbacks_by_token[request_id] = nil
            return
        end

        log:warn(string.format("MCP %s received unexpected response with no matching callback (request.id=%s)", self.server_log_name, request_id))
        return
    end

    -- Notifications (no ID). Currently only "notifications/progress" is handled.
    if message.method == "notifications/progress" then
        ---@cast message MCP_ProgressNotification
        local progress_token = message.params.progressToken
        local on_progress = self.progress_callbacks_by_token[progress_token] or function(params)
            log:info(string.format("MCP %s progress (NO CALLBACK): %s", self.server_log_name, vim.inspect(params)))
        end
        on_progress(message.params)
    end
end

--- Send a JSON-RPC request (with optional callback and progress).
--- Common to both transports; delegates transport-specific writing to write_to().
---@param self MCPClient
---@param request table
---@param callback ToolCallDoneCallback
---@param on_progress? ToolCallOnProgress
function MCPClient:send_request(request, callback, on_progress)
    if not request.id then
        request.id = self.counter
        self.counter = self.counter + 1
    end
    request.jsonrpc = "2.0"

    self.callbacks_by_request_id[request.id] = callback
    self.progress_callbacks_by_token[request.id] = on_progress
    self:write_to(request)
end

--- Send a JSON-RPC notification (no ID, no callback).
---@param self MCPClient
---@param notification { method: string, params?: any, [any]: any }
function MCPClient:send_notification(notification)
    notification.jsonrpc = "2.0"
    self:write_to(notification)
end

--- Build and send a tool/call request. Common to both transports.
---@param self MCPClient
---@param id string
---@param tool_name string
---@param args table
---@param callback ToolCallDoneCallback
---@param on_progress? ToolCallOnProgress
function MCPClient:tools_call(id, tool_name, args, callback, on_progress)
    self:send_request({
        id = id,
        method = "tools/call",
        params = {
            name = tool_name,
            arguments = args,
            _meta = { progressToken = id },
        },
    }, callback, on_progress)
end

--- Transport-specific method: write an encoded message to the server.
---@param self MCPClient
---@param message MCP_JSONRPCMessage
function MCPClient:write_to(message)
    error("MCPClient:write_to() must be implemented by subclass")
end

--- Transport-specific method: initialize the server connection.
--- STDIO performs the full init handshake; HTTP does tools/list directly.
---@param self MCPClient
function MCPClient:initialize()
    error("MCPClient:initialize() must be implemented by subclass")
end

-- ============================================================================
-- MCPStdioClient - handles communication via stdio (uv.spawn pipes)
-- ============================================================================

---@class MCPStdioClient : MCPClient
---@field stdin uv_pipe_t
---@field stdout uv_pipe_t
---@field stderr uv_pipe_t
---@field handle uv_handle_t
---@field pid integer
---@field pending_json string
local MCPStdioClient = setmetatable({}, { __index = MCPClient })
MCPStdioClient.__index = MCPStdioClient
---@param name string
---@param options table
---@return MCPStdioClient
function MCPStdioClient.new(name, options)
    local self = setmetatable({}, MCPStdioClient)

    self.server_log_name = "[" .. name:upper() .. "]"
    self.counter = 1
    self.callbacks_by_request_id = {}
    self.progress_callbacks_by_token = {}
    self.pending_json = ""

    -- Spawn the subprocess with pipes for stdin, stdout, stderr
    local handle, pid_or_error, error_name
    local stdin = uv.new_pipe(false)
    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    local function on_mcp_server_exit(code, signal)
        log:trace_on_exit_errors(code, signal)
        handle:close()

        if vim.v.exiting ~= nil then
            local msg = string.format(
                "MCP server %s EXITED\n\n  *NOTE: vim is not shutting down*\n\nRESTART NEOVIM if you need the server running",
                self.server_log_name
            )
            log:error(ansi.white_bold(ansi.red_bg(msg)))
            vim.schedule(function()
                vim.notify(msg, vim.log.levels.WARN)
            end)
        else
            log:error(string.format("MCP server %s exited (during neovim shutdown)", self.server_log_name))
        end
    end

    local process_env = uv_spawn.build_env_vars_for_uv_spawn_format(options)

    -- handle, pid_or_error, error_name = uv_spawn.uv_spawn("FAKE_COMMAND_TO_TEST_ERROR_RESULT", {
    handle, pid_or_error, error_name = uv_spawn.uv_spawn(options.command, {
        args = options.args,
        -- BTW env is not an override, it is all or none
        env = process_env,
        stdio = { stdin, stdout, stderr },
    }, on_mcp_server_exit)

    self.stdin = stdin
    self.stdout = stdout
    self.stderr = stderr
    self.handle = handle
    self.pid = pid_or_error

    -- Set up stdout reader with JSON-line buffering
    local function on_stdout(read_error, data)
        log:log_if_stdio_read_error(string.format("MCP on_stdout %s", self.server_log_name), read_error, data)
        if data == nil then
            return -- EOF
        end

        self.pending_json = self.pending_json .. data

        while true do
            local line, rest = self.pending_json:match("^(.-)\r?\n(.*)$")
            if not line then
                break
            end
            self.pending_json = rest

            local ok, response = safely.decode_json(line)
            if ok then
                self:dispatch_message(response)
            else
                log:error(string.format("MCP STDOUT decode error %s OK:", self.server_log_name), ok)
                log:error(string.format("MCP STDOUT decode error %s LINE:", self.server_log_name), line)
                log:error(string.format("MCP STDOUT decode error %s MSG:", self.server_log_name), vim.inspect(response))
            end
        end
    end

    uv.read_start(stdout, on_stdout)

    -- Set up stderr reader
    local function on_stderr(read_error, data)
        log:log_if_stdio_read_error(string.format("MCP on_stderr %s", self.server_log_name), read_error, data)
        if data == nil then
            return -- EOF
        end
        log:error(string.format("MCP %s STDERR:", self.server_log_name), ansi.red(data))
    end

    uv.read_start(stderr, on_stderr)

    return self
end

--- Write a message to the subprocess stdin (JSON + newline delimiter).
---@param self MCPStdioClient
---@param message MCP_JSONRPCMessage
function MCPStdioClient:write_to(message)
    local json = vim.json.encode(message)
    self.stdin:write(json .. "\n")
end

--- Perform the STDIO initialization sequence:
--- 1. send initialize request
--- 2. on success, send notifications/initialized
--- 3. fetch tools/list and register tools
---@param self MCPStdioClient
---@param on_done? fun() callback when this server is done
function MCPStdioClient:initialize(on_done)
    local client_init_params = {
        protocolVersion = "2024-11-05",
        capabilities = {
            roots = { listChanged = false },
        },
        clientInfo = {
            name = "ask-openai",
            version = "",
        },
    }

    self:send_request({ method = "initialize", params = client_init_params }, function(server_init)
        if server_init.error then
            local err = server_init.error
            local msg = ""
            if type(err) == "table" and err.message ~= nil then
                msg = string.format("MCP initialize error (SEE PATH below) %s: %s", self.server_log_name, err.message)
            else
                msg = string.format("MCP initialize error %s (no message)", self.server_log_name)
            end
            log:error(msg)
            vim.notify(msg, vim.log.levels.ERROR)
            return
        end

        -- Send initialized notification
        self:send_notification({ method = "notifications/initialized" })

        -- Fetch and register tools
        self:send_request({ method = "tools/list" }, function(response)
            if response.error then
                log:error(string.format("tools/list@%s error:", self.server_log_name), vim.inspect(response))
            else
                for _, tool in ipairs(response.result.tools) do
                    ---@cast tool MCP_Tool
                    -- log:info("tools/list:", tool)
                    tool.call = function(id, tool_name, args, callback, on_progress)
                        self:tools_call(id, tool_name, args, callback, on_progress)
                    end
                    M.tools_available[tool.name] = tool
                end
            end
            if on_done then
                vim.schedule(on_done)
            end
        end)
    end)
end

-- ============================================================================
-- MCPHttpServer - handles communication via HTTP POST + SSE responses
-- ============================================================================

---@class MCPHttpServer : MCPClient
---@field url string
local MCPHttpServer = setmetatable({}, { __index = MCPClient })
MCPHttpServer.__index = MCPHttpServer

---@param name string
---@param options table
---@return MCPHttpServer
function MCPHttpServer.new(name, options)
    local self = setmetatable({}, MCPHttpServer)

    self.server_log_name = "[" .. name:upper() .. "]"
    self.counter = 1
    self.callbacks_by_request_id = {}
    self.progress_callbacks_by_token = {}
    self.url = options.url

    return self
end

--- Write a message by spawning a curl process per request (POST + SSE).
---@param self MCPHttpServer
---@param message MCP_JSONRPCMessage
function MCPHttpServer:write_to(message)
    local json = vim.json.encode(message)

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)
    local handle

    local args = {
        "-i", "-s", "-X", "POST",
        "-H", "Content-Type: application/json",
        "-H", "Accept: application/json, text/event-stream",
        "-d", json,
        self.url,
    }

    local function on_curl_exit(code, signal)
        stdout:close()
        stderr:close()
        handle:close()
    end

    handle = uv_spawn.uv_spawn("curl", {
        args = args,
        stdio = { nil, stdout, stderr },
    }, on_curl_exit)

    -- Parse SSE response body
    local parser = SSEDataOnlyParser.new(function(data_value)
        ---@type MCP_JSONRPCMessage
        local rpc_message = vim.json.decode(data_value)
        self:dispatch_message(rpc_message)
    end)

    local headers_parsed = false
    local header_buffer = ""

    local function get_content_type(header_str)
        local content_type
        for line in header_str:gmatch("([^\r\n]+)") do
            local key, value = line:match("^(%S+):%s*(.+)$")
            if key and value and key:lower() == "content-type" then
                content_type = value
            end
        end
        return content_type
    end

    uv.read_start(stdout, function(read_err, data)
        if read_err then
            log:error(string.format("%s write_to_http on_stdout has read_err", self.server_log_name), vim.inspect(read_err))
            return
        end
        if data then
            if not headers_parsed then
                header_buffer = header_buffer .. data
                local header_end = header_buffer:find("\r?\n\r?\n")
                if header_end then
                    local raw_headers = header_buffer:sub(1, header_end)
                    local remaining = header_buffer:sub(header_end + 1)
                    local content_type = get_content_type(raw_headers)
                    if content_type ~= "text/event-stream" then
                        log:error(string.format("%s unexpected response type (Content-Type: %s)", self.server_log_name, content_type or "nil"))
                        return
                    end

                    headers_parsed = true
                    if #remaining > 0 then
                        parser:write(remaining)
                    end
                end
            else
                parser:write(data)
            end
        else
            parser:flush_dregs()
        end
    end)

    uv.read_start(stderr, function(read_err, data)
        if read_err then
            log:error(string.format("%s write_to_http on_stderr has read_err", self.server_log_name), vim.inspect(read_err))
            return
        end
        if data then
            log:error(string.format("%s write_to_http on_stderr has data", self.server_log_name), ansi.red(data))
        end
    end)
end

--- HTTP servers skip the init handshake — just fetch tools directly.
---@param self MCPHttpServer
---@param on_done? fun()
function MCPHttpServer:initialize(on_done)
    self:send_request({ method = "tools/list" }, function(response)
        if response.result and response.result.tools then
            for _, tool in pairs(response.result.tools) do
                ---@cast tool MCP_Tool
                tool.call = function(id, tool_name, args, callback, on_progress)
                    self:tools_call(id, tool_name, args, callback, on_progress)
                end
                M.tools_available[tool.name] = tool
            end
        elseif response.error then
            log:error(string.format("tools/list@%s error:", self.server_log_name), vim.inspect(response.error))
        end
        if on_done then
            vim.schedule(on_done)
        end
    end)
end

-- ============================================================================
-- Server startup helpers (public API)
-- ============================================================================

--- Create and initialize a STDIO-based MCP client.
---@param name string
---@param on_done? fun()
function start_mcp_server_stdio(name, on_done)
    local options = servers[name]
    local client = MCPStdioClient.new(name, options)
    client:initialize(on_done)
end

--- Create and initialize an HTTP-based MCP client.
---@param name string
---@param on_done? fun()
function start_mcp_server_http(name, on_done)
    local options = servers[name]
    local client = MCPHttpServer.new(name, options)
    client:initialize(on_done)
end

---@type table<string, MCP_Tool>
M.tools_available = {}

---@type boolean
M.ready = false

-- Track server initialization progress
local server_count = 0
local initialized_count = 0

local function mark_server_initialized()
    initialized_count = initialized_count + 1
    if initialized_count >= server_count then
        M.ready = true
        log:info('All MCP servers initialized (' .. initialized_count .. '/' .. server_count .. ')')
    end
end

for name, server in pairs(servers) do
    server_count = server_count + 1
    if server.transport == "stdio" then
        start_mcp_server_stdio(name, mark_server_initialized)
    elseif server.transport == "http" then
        start_mcp_server_http(name, mark_server_initialized)
    else
        error(string.format("unsupported transport %s for server %s", server.transport, name))
    end
end

function M.setup()
    vim.api.nvim_create_user_command("AskDumpMcpTools", function()
        local message = vim.inspect(M.tools_available)
        log:info(message)
        print(message)
    end, { nargs = 0 })
end

---@return OpenAITool
---@param mcp_tool MCP_Tool
function M.openai_tool(mcp_tool)
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
            description = mcp_tool.description,
            parameters = params,
        }
    }
end

---@param tool_name string
---@return boolean
function M.handles_tool(tool_name)
    local tool = M.tools_available[tool_name]
    return tool ~= nil
end

---@param tool_call ToolCall
---@param callback ToolCallDoneCallback
---@param on_progress? ToolCallOnProgress
function M.send_tool_call(tool_call, callback, on_progress)
    -- LEFT OFF HERE TRACING passing of progress
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
    ---@type MCP_Tool | nil
    local tool = M.tools_available[name]
    if tool == nil then
        callback(plumbing.create_tool_call_output_for_error_message("Invalid MCP tool name: " .. name))
        return
    end

    local function decode_tool_args(args)
        if type(args) == "string" then
            return vim.json.decode(args)
        end
        if type(args) == "table" then
            return args
        end
        log:error(string.format("Tool [%s] arguments has unexpected type: %s", tool_call["function"].name, type(args)))
        return {}
    end

    local args_decoded = decode_tool_args(tool_call["function"].arguments)
    tool.call(tool_call.id, name, args_decoded, vim.schedule_wrap(callback), on_progress)
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
        local commits = files.read_text(run_process_dir .. "/commits.md"):gsub("<<COAUTHOR_NAME>>", "gptoss120b") -- TODO: revisit model slug mapping
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
