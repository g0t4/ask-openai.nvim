--- Fake model server for deterministic predictions integration testing.
---
--- Replaces `curl.spawn` (the same seam the agents fake server uses) with a
--- scripted SSE emitter so predictions tests can exercise the full UI pipeline
--- (extmarks, accepts, cursor movement) without a real llama-server backend.
---
--- Predictions differ from agents in a few important ways:
---   * the predictions frontend has no `trace` and no queued messages/tool calls,
---   * it feeds SSE through `on_parsed_data_sse` and `on_curl_exited_successfully`,
---   * it parses both chat-completions SSE (delta.content) and raw-completions SSE
---     (content + stop), depending on the configured FIM model/endpoint.
---
--- Usage:
---   local fake = require("ask-openai.predictions.fake_model_server")
---   fake.install()
---   fake.script("rewrite", {
---     fake.content_chunk("def add(x, y):\n    return x + y"),
---     fake.finish_chunk("stop"),
---   })
---   fake.use_script("rewrite")
---   -- run test...
---   fake.uninstall()

local log = require("devtools.logs.logger").universal()

---@class PredictionsFakeModelServer
local FakeModelServer = {}

---@type table<string, table[]> -- script name => list of SSE chunk tables
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

---@type string -- model name used in SSE chunks (can be set to match configured model)
local model_name = "fake-model"

---@type fun(request: table)|nil -- hook called before chunks are delivered
local on_request_started = nil

---@type fun(request: table)|nil -- hook called after all chunks are delivered
local on_request_completed = nil

---@type integer -- current chunk index (for async delivery)
local current_chunk_index = 0

---@type uv_timer_t|nil -- timer handle for async delivery
local delivery_timer = nil

---@type table|nil -- request currently being delivered
local active_request = nil

---@type table|nil -- the frontend receiving the fake SSEs
local active_frontend = nil

---@type table[] -- chunks for the active delivery
local active_chunks = {}

--- Build an SSE chunk table in the shape the predictions frontend expects.
--- The predictions frontend parses either chat-completions or raw-completions
--- SSE depending on the FIM endpoint, so we build a generic chunk and let the
--- caller choose which fields to populate.
---@param opts table
---@return table
local function build_sse_chunk(opts)
    opts = opts or {}
    local choice = {}
    local delta = opts.delta or {}

    if delta.role or delta.content or delta.reasoning_content then
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
        model = opts.model or model_name,
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

    -- * raw completions fields (used by the /completions endpoint)
    if opts.raw_content ~= nil then
        sse.content = opts.raw_content
    end
    if opts.stop ~= nil then
        sse.stop = opts.stop
    end
    if opts.stop_type ~= nil then
        sse.stop_type = opts.stop_type
    end

    return sse
end

--- Convenience: build a chat-completions content SSE chunk (delta.content).
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

--- Convenience: build a chat-completions reasoning SSE chunk (delta.reasoning_content).
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

--- Convenience: build a chat-completions finish_reason SSE chunk.
---@param finish_reason string
---@param timings? table -- llama-server timings (marks the last SSE chunk)
---@return table
function FakeModelServer.finish_chunk(finish_reason, timings)
    return build_sse_chunk({
        delta = {},
        finish_reason = finish_reason or "stop",
        timings = timings,
    })
end

--- Convenience: build a raw-completions content SSE chunk (/completions endpoint).
---@param content string
---@param stop boolean -- whether this chunk marks the end of generation
---@return table
function FakeModelServer.raw_content_chunk(content, stop)
    return build_sse_chunk({
        raw_content = content,
        stop = stop or false,
    })
end

--- Convenience: build a raw-completions stop SSE chunk (final token).
---@param stop_type string
---@return table
function FakeModelServer.raw_stop_chunk(stop_type)
    return build_sse_chunk({
        raw_content = "",
        stop = true,
        stop_type = stop_type or "eos",
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

--- Set the model name used in generated SSE chunks.
---@param name string
function FakeModelServer.set_model_name(name)
    model_name = name
end

--- Set a hook called when a request starts.
---@param hook fun(request: table)|nil
function FakeModelServer.set_on_request_started(hook)
    on_request_started = hook
end

--- Set a hook called when a request completes.
---@param hook fun(request: table)|nil
function FakeModelServer.set_on_request_completed(hook)
    on_request_completed = hook
end

--- Get the number of requests served.
---@return integer
function FakeModelServer.get_request_count()
    return request_count
end

--- Reset request count and in-flight delivery state.
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

    -- * schedule the next chunk (or the completion check)
    --   Always schedule the next delivery even for the final chunk so that
    --   the next invocation (which sees `chunk == nil`) triggers completion.
    if async_delivery then
        if delivery_timer then
            pcall(function()
                if not delivery_timer:is_closing() then
                    delivery_timer:stop()
                    delivery_timer:close()
                end
            end)
            delivery_timer = nil
        end
        delivery_timer = vim.uv.new_timer()
        delivery_timer:start(default_chunk_delay_ms, 0, function()
            vim.schedule(deliver_next_chunk)
        end)
    end
end

--- The `spawn` replacement. Feeds scripted chunks through the predictions
--- frontend exactly like a real streaming curl would.
---@param request table
---@param frontend table
function FakeModelServer.spawn(request, frontend)
    request_count = request_count + 1

    -- * ensure request has required fields (mirror real Curl.spawn behavior)
    request.body = request.body or {}
    request.body.stream = true

    -- * pick up the scripted chunks
    if current_script_name and scripts[current_script_name] then
        active_chunks = scripts[current_script_name]
        log:info("PredictionsFakeModelServer: using script '" .. current_script_name .. "' with "
            .. #active_chunks .. " chunks")
    else
        -- * default: a simple completion response
        active_chunks = {
            FakeModelServer.content_chunk("    # fake default prediction"),
            FakeModelServer.finish_chunk("stop"),
        }
        log:warn("PredictionsFakeModelServer: no script selected, using default response")
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

--- Install the fake server by monkey-patching the curl module used by the
--- predictions frontend. This is reversible via uninstall().
function FakeModelServer.install()
    if is_installed then
        return
    end

    local curl = require("ask-openai.backends.curl")
    FakeModelServer._original_spawn = curl.spawn
    curl.spawn = FakeModelServer.spawn
    is_installed = true
    log:info("PredictionsFakeModelServer: installed")
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
    log:info("PredictionsFakeModelServer: uninstalled")

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
