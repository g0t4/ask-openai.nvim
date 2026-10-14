--- Fake model server for deterministic integration testing.
---
--- Replaces `curl.spawn` in AgentsFrontend with a scripted SSE emitter so
--- tests can exercise agent behavior (queued messages, interrupts, tool calls)
--- without a real llama-server or MCP backend.
---
--- Usage:
---   local fake = require("ask-openai.agents.fake_model_server")
---   fake.install()
---   fake.script("response", {
---     { delta = { role = "assistant", content = "Hello" } },
---     { delta = { content = " world" } },
---     { delta = {}, finish_reason = "stop" },
---   })
---   -- run test...
---   fake.uninstall()

local log = require("devtools.logs.logger").universal()
local CurlRequestForTrace = require("ask-openai.agents.curl_request_for_trace")

---@class FakeModelServer
local FakeModelServer = {}

---@type table<string, table[]> -- script name => list of SSE chunks (tables)
local scripts = {}

---@type string|nil -- current script name
local current_script_name = nil

---@type boolean -- whether the fake server is installed
local is_installed = false

---@type number -- how many requests have been served (for asserting request counts)
local request_count = 0

---@type integer -- delay (ms) between SSE chunks when delivering asynchronously
local default_chunk_delay_ms = 10

---@type boolean -- if true, deliver chunks asynchronously (default); if false, synchronously
local async_delivery = true

---@type fun(request: CurlRequestForTrace)|nil -- hook called before chunks are delivered
local on_request_started = nil

---@type fun(request: CurlRequestForTrace)|nil -- hook called after all chunks are delivered
local on_request_completed = nil

---@type integer -- current chunk index (for async delivery)
local current_chunk_index = 0

---@type uv_timer_t|nil -- timer handle for async delivery
local delivery_timer = nil

---@type CurlRequestForTrace|nil -- request currently being delivered
local active_request = nil

---@type table|nil -- the frontend receiving the fake SSEs
local active_frontend = nil

---@type table[] -- chunks for the active delivery
local active_chunks = {}

--- Build an SSE chunk table in the shape the frontend expects.
---@param opts table
---@return table
local function build_sse_chunk(opts)
    opts = opts or {}
    local choice = {}
    local delta = opts.delta or {}

    if delta.role or delta.content or delta.reasoning_content or delta.tool_calls then
        choice.delta = delta
    else
        choice.delta = {}
    end

    if opts.finish_reason ~= nil then
        choice.finish_reason = opts.finish_reason
    else
        choice.finish_reason = vim.NIL
    end

    choice.index = opts.index or 0

    local sse = {
        choices = { choice },
        model = opts.model or "fake-model",
        object = "chat.completion.chunk",
        created = opts.created or os.time(),
        id = "chatcmpl-fake-" .. tostring(request_count),
    }

    if opts.timings then
        sse.timings = opts.timings
    end

    if opts.error then
        sse.error = opts.error
    end

    return sse
end

--- Convenience: build a content SSE chunk.
---@param content string
---@param role? string
---@return table
function FakeModelServer.content_chunk(content, role)
    return build_sse_chunk({
        delta = {
            role = role or "assistant",
            content = content,
        },
    })
end

--- Convenience: build a reasoning content SSE chunk.
---@param reasoning string
---@param role? string
---@return table
function FakeModelServer.reasoning_chunk(reasoning, role)
    return build_sse_chunk({
        delta = {
            role = role or "assistant",
            reasoning_content = reasoning,
        },
    })
end

--- Convenience: build a finish_reason SSE chunk.
---@param finish_reason string
---@return table
function FakeModelServer.finish_chunk(finish_reason)
    return build_sse_chunk({
        delta = {},
        finish_reason = finish_reason or "stop",
    })
end

--- Convenience: build a tool_call SSE chunk.
---@param opts {id: string, name: string, arguments: string, index?: integer}
---@return table
function FakeModelServer.tool_call_chunk(opts)
    local call_delta = {
        index = opts.index or 0,
        id = opts.id or "call_" .. tostring(request_count),
        type = "function",
        ["function"] = {
            name = opts.name,
            arguments = opts.arguments or "",
        },
    }
    return build_sse_chunk({
        delta = {
            role = "assistant",
            tool_calls = { call_delta },
        },
    })
end

--- Convenience: build a tool_call argument chunk (continuation).
---@param args string
---@param index integer
---@return table
function FakeModelServer.tool_call_args_chunk(args, index)
    return build_sse_chunk({
        delta = {
            tool_calls = {
                {
                    index = index or 0,
                    ["function"] = {
                        arguments = args,
                    },
                },
            },
        },
    })
end

--- Register a scripted response sequence.
---@param name string
---@param chunks table[] -- list of SSE chunk tables
function FakeModelServer.script(name, chunks)
    scripts[name] = chunks
end

--- Set which script the next request will use.
---@param name string
function FakeModelServer.use_script(name)
    current_script_name = name
end

--- Get the list of scripts (for introspection/testing).
---@return table<string, table[]>
function FakeModelServer.get_scripts()
    return scripts
end

--- Clear all scripts.
function FakeModelServer.clear_scripts()
    scripts = {}
    current_script_name = nil
end

--- Set the delay between chunk deliveries.
---@param delay_ms number
function FakeModelServer.set_chunk_delay_ms(delay_ms)
    default_chunk_delay_ms = delay_ms
end

--- Set whether chunks are delivered asynchronously (default true).
---@param value boolean
function FakeModelServer.set_async_delivery(value)
    async_delivery = value
end

--- Set a hook called when a request starts.
---@param hook fun(request: CurlRequestForTrace)|nil
function FakeModelServer.set_on_request_started(hook)
    on_request_started = hook
end

--- Set a hook called when a request completes.
---@param hook fun(request: CurlRequestForTrace)|nil
function FakeModelServer.set_on_request_completed(hook)
    on_request_completed = hook
end

--- Get the number of requests served.
---@return integer
function FakeModelServer.get_request_count()
    return request_count
end

--- Reset request count.
function FakeModelServer.reset()
    request_count = 0
    current_script_name = nil
    active_request = nil
    active_frontend = nil
    active_chunks = {}
    current_chunk_index = 0
    on_request_started = nil
    on_request_completed = nil
end

--- Deliver the next chunk (or finish if all chunks delivered).
local function deliver_next_chunk()
    if not active_request or not active_frontend then
        return
    end

    current_chunk_index = current_chunk_index + 1
    local chunk = active_chunks[current_chunk_index]

    if not chunk then
        -- * all chunks delivered => signal completion
        if delivery_timer then
            delivery_timer:stop()
            delivery_timer:close()
            delivery_timer = nil
        end

        if active_frontend.on_curl_exited_successfully then
            active_frontend.on_curl_exited_successfully()
        end

        if on_request_completed then
            on_request_completed(active_request)
        end

        active_request = nil
        active_frontend = nil
        active_chunks = {}
        return
    end

    -- * feed the SSE chunk through the frontend
    if active_frontend.on_parsed_data_sse then
        active_frontend.on_parsed_data_sse(chunk)
    end

    -- * schedule the next chunk
    if async_delivery and #active_chunks > current_chunk_index then
        delivery_timer = vim.uv.new_timer()
        delivery_timer:start(default_chunk_delay_ms, 0, function()
            vim.schedule(deliver_next_chunk)
        end)
    end
end

--- The `spawn` replacement. Creates a CurlRequestForTrace from the same
--- params the real `curl.spawn` would receive, then feeds scripted chunks
--- through the frontend.
---@param request CurlRequestForTrace
---@param frontend StreamingFrontend
function FakeModelServer.spawn(request, frontend)
    request_count = request_count + 1

    -- * ensure request has required fields (mirror real Curl.spawn behavior)
    request.body = request.body or {}
    request.body.stream = true

    -- * register the request on the trace (mirror then_get_assistant_response)
    if frontend.trace then
        frontend.trace:set_last_request(request)
    end

    -- * pick up the scripted chunks
    if current_script_name and scripts[current_script_name] then
        active_chunks = scripts[current_script_name]
        log:info("FakeModelServer: using script '" .. current_script_name .. "' with "
            .. #active_chunks .. " chunks")
    else
        -- * default: a simple greeting response
        active_chunks = {
            FakeModelServer.content_chunk("Hello from fake model server!", "assistant"),
            FakeModelServer.finish_chunk("stop"),
        }
        log:warn("FakeModelServer: no script selected, using default response")
    end

    active_request = request
    active_frontend = frontend
    current_chunk_index = 0

    if on_request_started then
        on_request_started(request)
    end

    -- * deliver chunks
    if async_delivery then
        -- * deliver first chunk synchronously, then schedule the rest
        deliver_next_chunk()
        -- * the rest are delivered via timer in deliver_next_chunk
    else
        -- * deliver all chunks synchronously
        while active_request do
            deliver_next_chunk()
        end
    end
end

--- Install the fake server by monkey-patching the curl module used by frontend.
--- This is reversible via uninstall().
function FakeModelServer.install()
    if is_installed then
        return
    end

    local curl = require("ask-openai.backends.curl")
    FakeModelServer._original_spawn = curl.spawn
    curl.spawn = FakeModelServer.spawn
    is_installed = true
    log:info("FakeModelServer: installed")
end

--- Uninstall the fake server, restoring the original curl.spawn.
function FakeModelServer.uninstall()
    if not is_installed then
        return
    end

    local curl = require("ask-openai.backends.curl")
    if FakeModelServer._original_spawn then
        curl.spawn = FakeModelServer._original_spawn
        FakeModelServer._original_spawn = nil
    end
    is_installed = false
    log:info("FakeModelServer: uninstalled")

    -- * cleanup any pending delivery
    if delivery_timer then
        delivery_timer:stop()
        delivery_timer:close()
        delivery_timer = nil
    end
    active_request = nil
    active_frontend = nil
    active_chunks = {}
    current_chunk_index = 0
end

--- Whether the fake server is installed.
---@return boolean
function FakeModelServer.is_installed()
    return is_installed
end

return FakeModelServer
