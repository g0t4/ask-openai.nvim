local log = require("ask-openai.logs.logger").predictions()
local SSEDataOnlyParser = require("ask-openai.backends.sse.data_only_parser")
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
    -- mcp_docs = {
    --     transport = "http",
    --     url = "https://modelcontextprotocol.io/mcp",
    -- }
    -- langchain_docs = {
    --     transport = "http",
    --     url = "https://docs.langchain.com/mcp",
    -- }
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

    local counter = 1
    local callbacks_by_request_id = {}
    local progress_callbacks_by_token = {} -- TODO use these for dispatching progress notifications back to tool caller

    ---@param message MCP_JSONRPCMessage
    local function on_server_response_stdio(message)
        -- Response object (success or failure)
        -- - Server does NOT send response to notifications
        -- - https://www.jsonrpc.org/specification#response_object
        --   - ID of request is required
        --   - Either `error` or `result` is required
        --     - NOT BOTH
        --     - `result` object not constrained by spec
        --     - `error` object has code/message/data properties: https://www.jsonrpc.org/specification#error_object
        if message.error then
            log:error(string.format("MCP %s STDIO error response:", server_log_name), vim.inspect(message.error))
        end

        -- log:info("MCP response:", vim.inspect(server_response))
        local request_id = message.id
        if request_id then
            local callback = callbacks_by_request_id[request_id]
            if callback then
                -- PRN strip out errors?
                --   not sure I really ever use error right now!
                --   PRN find out if/how I should be using JSONRPC error objects? (look at other MCP servers, try with fetch an invalid URL?)
                --   IOTW only pass result? => callback(server_response.result)
                callback(message)
                callbacks_by_request_id[request_id] = nil
                progress_callbacks_by_token[request_id] = nil
            else
                log:error(string.format("MCP %s received unexpected response with no matching callback (request.id=%s)", server_log_name, request_id))
            end
            return
        end

        if message.method == "notifications/progress" then
            ---@cast message MCP_ProgressNotification
            local progress_token = message.params.progressToken
            local on_progress = progress_callbacks_by_token[progress_token]
            if on_progress then
                on_progress(message.params)
            else
                log:info(string.format("MCP %s progress (no caller): %s", server_log_name, vim.inspect(message.params)))
            end
            -- [INFO ] MCP response: {
            --   jsonrpc = "2.0",
            --   method = "notifications/progress",
            --   params = {
            --     progress = 16,
            --     progressToken = "progress_wONXcTyWCrfdSFxA7CXd099DWvDQSxn2",
            --     total = 100 -- this is from simple example of count to 100
            --   }
            -- }
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
                on_server_response_stdio(response)
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

    ---@param message MCP_JSONRPCMessage
    local function write_to_stdio(message)
        local json = vim.json.encode(message)
        -- log:info(string.format("MCP write %s:", server_log_name), json)
        stdin:write(json .. "\n")
    end

    ---@param request table
    ---@param callback ToolCallDoneCallback
    ---param on_progress ToolCallOnProgress
    local function send_request(request, callback, on_progress)
        -- Regular request (with optional callback). ID is always set unless caller explicitly provides one.
        if not request.id then
            request.id = counter
            counter = counter + 1
        end
        request.jsonrpc = "2.0"

        callbacks_by_request_id[request.id] = callback
        progress_callbacks_by_token[request.id] = on_progress -- progressToken == request.id in my setup
        write_to_stdio(request)
    end

    --- Send a JSON-RPC notification
    ---@param notification { method: string, params?: any, [any]: any }
    local function send_notification(notification)
        -- * notifications CANNOT have ID: https://www.jsonrpc.org/specification#notification
        -- BTW notification is a type of request (w/o id)
        -- notifications do not have callbacks nor progress
        -- modelcontextprotocol uses "notifications/" method prefix, i.e.: notifications/initialized and notifications/tools/list_changed
        notification.jsonrpc = "2.0"
        write_to_stdio(notification)
    end

    ---@param callback fun(response: MCP_ListToolsResult)
    local function tools_list(callback)
        send_request({ method = "tools/list" }, callback)
    end

    local function cancel_tool_call(tool_call_id, reason)
        -- TODO plug this into agent abort, when tool call(s) are outstanding
        send_notification({
            method = "notifications/initialized",
            params = {
                -- TODO confirm tool_call's ID is the original tool call's request.id
                requestId = tool_call_id,
                reason = reason,
            },
        })
    end

    local function tools_call(id, tool_name, args, callback, on_progress)
        -- PRN/TODO btw your downstream code uses result object for almost everything, even tool call failures... that is probably fine but I should find out if a failed tool call is suppose to be presented as an error object on the response or as-is with result.isError etc?
        send_request({
            id = id,
            method = "tools/call",
            params = {
                name = tool_name,
                arguments = args,
                -- TODO! receive and pass back notifications/progress to tool call clients
                _meta = { progressToken = id },
            },
        }, callback, on_progress)
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

    send_request({ method = "initialize", params = client_init_params }, function(server_init)
        -- log:trace(string.format("MCP initialize response %s:", server_log_name), vim.inspect(server_init))

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
        send_notification({ method = "notifications/initialized" })

        -- PRN do I need to wait before tools/list ? IIUC notifications/initialized doesn't get a server response... so in this case, I am not waiting to send tools/list:
        tools_list(function(response)
            if response.error then
                log:error(string.format("tools/list@%s error:", server_log_name), vim.inspect(response))
                return
            end
            for _, tool in ipairs(response.result.tools) do
                ---@cast tool MCP_Tool
                log:info("tools/list:", vim.inspect(tool))
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

    -- currently I don't do anything with running_servers, so I don't really need to return an object, short of GC perhaps
    --  TODO any GC issues after a while? if so, should I return references to stdin/out/err pipes or smth else?
    -- return {}
end

local function start_mcp_server_http(name)
    local server_log_name = "[" .. name:upper() .. "]"
    local options = servers[name]
    local counter = 1
    local callbacks_by_request_id = {}
    local progress_callbacks_by_token = {} -- TODO use these for dispatching progress notifications back to tool caller

    local function on_data_sse(data_value)
        -- log:trace(string.format("MCP %s JSONRPC on_data_sse data_value:", server_log_name), vim.inspect(data_value))
        ---@type MCP_JSONRPCMessage
        local message = vim.json.decode(data_value)
        -- log:trace(string.format("MCP %s JSONRPC response:", server_log_name), vim.inspect(rpc_response))
        if message.error then
            log:error(string.format("MCP %s JSONRPC response error:", server_log_name), vim.inspect(message.error))
        end

        local request_id = message.id
        if request_id then
            -- request.id implies this is a response
            ---@cast message MCP_JSONRPCResponse
            local callback = callbacks_by_request_id[request_id]
            if callback then
                callback(message)
                -- avoid leaking memory:
                callbacks_by_request_id[request_id] = nil
                progress_callbacks_by_token[request_id] = nil
                return
            end

            log:warn(string.format("MCP %s JSONRPC response.id has no corresponding callback:", server_log_name))
            return
        end

        if message.method == "notifications/progress" then
            ---@cast message MCP_ProgressNotification
            local progress_token = message.params.progressToken
            local on_progress = progress_callbacks_by_token[progress_token]
            if on_progress then
                on_progress(message.params)
            else
                log:info(string.format("MCP %s Progress (no caller): %s", server_log_name, vim.inspect(message.params)))
            end
        end
    end


    ---@param request MCP_JSONRPCRequest
    ---@param callback ToolCallDoneCallback
    ---@param on_progress ToolCallOnProgress
    local function send_request(request, callback, on_progress)
        if not request.id then
            request.id = counter
            counter = counter + 1
        end
        request.jsonrpc = "2.0"
        callbacks_by_request_id[request.id] = callback
        progress_callbacks_by_token[request.id] = on_progress -- progress_token == request.id in my setup

        local json = vim.json.encode(request)

        local stdout = uv.new_pipe(false)
        local stderr = uv.new_pipe(false)
        local handle
        local args = {
            "-i", "-s", "-X", "POST",
            "-H", "Content-Type: application/json",
            "-H", "Accept: application/json, text/event-stream",
            "-d", json,
            options.url,
        }

        local function on_exit(code, signal)
            -- log:info(string.format("%s send_request_http on_exit", server_log_name), code, signal)
            -- Close pipes after process exits.
            stdout:close()
            stderr:close()
            handle:close()
        end

        handle = uv.spawn("curl", {
            args = args,
            stdio = { nil, stdout, stderr },
        }, on_exit)

        -- Include response headers with `-i`. We'll parse them before feeding body to the SSE parser.
        local parser = SSEDataOnlyParser.new(on_data_sse)
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
            -- log:info(string.format("%s send_request_http on_stdout", server_log_name), vim.inspect(data))
            if read_err then
                log:error(string.format("%s send_request_http on_stdout has read_err", server_log_name), vim.inspect(read_err))
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
                        -- log:info(string.format("%s content-type header: %s", server_log_name, content_type))
                        if content_type ~= "text/event-stream" then
                            log:error(string.format("%s unexpected response type (Content-Type: %s)", server_log_name, content_type or "nil"))
                            -- Abort further processing; downstream callbacks will not be invoked.
                            -- PRN implement application/json support? I don't think I will need this with HTTP POST based reequests
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
                log:error(string.format("%s send_request_http on_stderr has read_err", server_log_name), vim.inspect(read_err))
                return
            end
            if data then
                log:error(string.format("%s send_request_http on_stderr has data", server_log_name), ansi.red(data))
            end
        end)
    end

    local function tools_call(id, tool_name, args, callback, on_progress)
        send_request({
            id = id,
            method = "tools/call",
            params = {
                name = tool_name,
                arguments = args,
                _meta = { progressToken = id },
            },
        }, callback, on_progress)
    end

    send_request({ method = "tools/list" }, function(response)
        local tools = response.result.tools
        for _, tool in pairs(tools) do
            ---@cast tool MCP_Tool
            tool.call = tools_call
            M.tools_available[tool.name] = tool
        end
    end)
end

-- M.running_servers = {}
---@type table<string, MCP_Tool>
M.tools_available = {}

for name, server in pairs(servers) do
    local server_log_name = "[" .. name:upper() .. "]"
    -- log:trace("starting mcp server " .. server_log_name .. " with transport: " .. server.transport)

    if server.transport == "stdio" then
        start_mcp_server_stdio(name)
    elseif server.transport == "http" then
        start_mcp_server_http(name)
    else
        error(string.format("unsupported transport %s for server %s", server.transport, name))
    end
    -- M.running_servers[name] = mcp
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

    -- PRN timeout mechanism? might be a good spot to wrap an async timer to check back (wait for the need to arise)

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
