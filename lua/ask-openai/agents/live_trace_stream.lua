-- Local, one-way trace subscription. The agent never waits for a viewer.
local uv = vim.uv or vim.loop
local M = {}
local Publisher = {}
Publisher.__index = Publisher

local function now()
    local seconds, microseconds = uv.gettimeofday()
    return seconds + microseconds / 1000000
end

function Publisher.new(path, interval_ms)
    return setmetatable({ path = path, interval_ms = interval_ms or 50, clients = {}, sequence = 0 }, Publisher)
end

local function close(handle)
    if handle and not handle:is_closing() then handle:close() end
end

function Publisher:drop(client)
    self.clients[client] = nil
    close(client)
end

function Publisher:start()
    if self.server then return true end
    vim.fn.mkdir(vim.fn.fnamemodify(self.path, ":h"), "p", 448)
    local server = uv.new_pipe(false)
    local ok, err = server:bind(self.path)
    if not ok then close(server); return nil, err end
    uv.fs_chmod(self.path, 384) -- 0600: trace contents are private to this user.
    self.server = server
    local listening, listen_error = server:listen(16, function(accept_error)
        if accept_error then return end
        local client = uv.new_pipe(false)
        if not server:accept(client) then close(client); return end
        self.clients[client] = { committed_count = 0 }
        -- The protocol is read-only; discard input and detect disconnects.
        client:read_start(function(read_error, data)
            if read_error or not data then self:drop(client) end
        end)
        vim.schedule(function() self:send(client, true) end)
    end)
    if not listening then self:close(); return nil, listen_error end
    return true
end

local function partial_message(message)
    local result = { role = message.role or "assistant", content = message.content or "",
        reasoning_content = message.reasoning_content, _partial = true }
    local metadata = require("ask-openai.backends.response_metadata")
    metadata.copy(message.last_sse or {}, result)
    result.tool_calls = {}
    for _, call in ipairs(message.tool_calls or {}) do
        result.tool_calls[#result.tool_calls + 1] = { id = call.id, type = call.type or "function",
            ["function"] = { name = (call["function"] or {}).name,
                arguments = (call["function"] or {}).arguments or "" } }
    end
    return result
end

function Publisher:send(client, full)
    local state = self.clients[client]
    if not state or not self.trace then return end
    -- Bounded backpressure: a slow subscriber reconnects for a fresh snapshot.
    if client:get_write_queue_size() > 1024 * 1024 then self:drop(client); return end
    local trace = self.trace
    local prefix = (not full and state.trace == trace) and math.min(state.committed_count, #trace.messages) or 0
    -- Undo/resume can replace messages without changing the history length.
    for index = 1, prefix do
        if trace.messages[index] ~= (state.history or {})[index] then prefix = index - 1; break end
    end
    local messages = {}
    for index = prefix + 1, #trace.messages do messages[#messages + 1] = trace.messages[index] end
    if self.request then
        for _, message in ipairs(self.request.accumulated_model_response_messages or {}) do
            messages[#messages + 1] = partial_message(message)
        end
    end
    local event = { version = 1, type = "snapshot", sequence = self.sequence,
        trace_path = vim.fn.stdpath("state") .. "/ask-openai/agents/" .. trace.start_time .. "-trace.json",
        replace_from = prefix, messages = messages, status = self.status,
        model_name = self.model_name, updated_at = self.updated_at }
    local ok, encoded = pcall(vim.json.encode, event)
    if not ok then return end
    local written = client:write(encoded .. "\n", function(err)
        if err then self:drop(client) end
    end)
    if not written then self:drop(client); return end
    state.trace, state.committed_count = trace, #trace.messages
    state.history = {}
    for index, message in ipairs(trace.messages) do state.history[index] = message end
end

function Publisher:flush()
    self.pending = false
    for client in pairs(self.clients) do self:send(client, false) end
end

function Publisher:changed(trace, model_name)
    if self.trace ~= trace then return end
    self.model_name = model_name or self.model_name
    self.sequence = self.sequence + 1
    self.updated_at = now()
    if self.pending or not next(self.clients) then return end
    self.pending = true
    vim.defer_fn(function() self:flush() end, self.interval_ms)
end

function Publisher:begin_request(trace, request)
    self.trace, self.request, self.status = trace, request, "streaming"
    self.model_name = request.body and request.body.model
    self:changed(trace)
end

function Publisher:finish_request(trace, status)
    if self.trace ~= trace then return end
    self.request, self.status = nil, status or "idle"
    self:changed(trace)
end

function Publisher:stop(trace, status)
    if self.trace ~= trace then return end
    self.status = status or "cancelled"
    self:changed(trace)
end

function Publisher:close()
    for client in pairs(self.clients) do self:drop(client) end
    close(self.server)
    self.server = nil
    uv.fs_unlink(self.path)
end

M.Publisher = Publisher
local publisher
function M.begin_request(trace, request)
    if not publisher then
        local path = vim.fn.stdpath("state") .. "/ask-openai/agents/live-" .. vim.fn.getpid() .. ".sock"
        local candidate = Publisher.new(path)
        local ok, started = pcall(candidate.start, candidate)
        if not ok or not started then return end -- Optional viewer must never block inference.
        publisher = candidate
        vim.api.nvim_create_autocmd("VimLeavePre", { once = true, callback = function() publisher:close() end })
    end
    publisher:begin_request(trace, request)
end
function M.changed(trace, model_name) if publisher then publisher:changed(trace, model_name) end end
function M.finish_request(trace, status) if publisher then publisher:finish_request(trace, status) end end
function M.stop(trace, status) if publisher then publisher:stop(trace, status) end end

return M
