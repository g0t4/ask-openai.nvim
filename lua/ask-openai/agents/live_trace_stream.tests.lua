local Publisher = require("ask-openai.agents.live_trace_stream").Publisher
local uv = vim.uv or vim.loop

describe("live trace Unix socket publisher", function()
    local publisher, clients, path
    before_each(function()
        path = vim.fn.tempname() .. ".sock"
        publisher = Publisher.new(path, 5)
        clients = {}
        assert.is_true(publisher:start())
    end)
    after_each(function()
        for _, client in ipairs(clients) do
            if not client:is_closing() then client:close() end
        end
        publisher:close()
    end)
    local function connect()
        local client, events, pending = uv.new_pipe(false), {}, ""
        clients[#clients + 1] = client
        client:connect(path, function(err)
            assert.is_nil(err)
            client:read_start(function(read_error, data)
                assert.is_nil(read_error)
                if not data then return end
                pending = pending .. data
                while pending:find("\n", 1, true) do
                    local newline = pending:find("\n", 1, true)
                    events[#events + 1] = vim.json.decode(pending:sub(1, newline - 1))
                    pending = pending:sub(newline + 1)
                end
            end)
        end)
        return events
    end
    local function wait_events(events, count)
        assert.is_true(vim.wait(1000, function() return #events >= count end, 5))
        return events[#events]
    end

    it("streams partial messages and reconciles committed history without duplication", function()
        local trace = { start_time = 123, messages = { { role = "user", content = "hi" } } }
        local request = { body = { model = "configured" }, accumulated_model_response_messages = {} }
        publisher:begin_request(trace, request)
        local events = connect()
        local initial = wait_events(events, 1)
        assert.equals(0, initial.replace_from)
        assert.equals("hi", initial.messages[1].content)
        local rx = { role = "assistant", reasoning_content = "thinking", content = "partial [",
            tool_calls = { { id = "call", ["function"] = { name = "run_bash", arguments = '{"cmd":' } } } }
        request.accumulated_model_response_messages[1] = rx
        for _ = 1, 10 do publisher:changed(trace, "actual") end
        local partial = wait_events(events, 2)
        assert.equals(1, partial.replace_from)
        assert.equals(1, #partial.messages)
        assert.is_true(partial.messages[1]._partial)
        assert.equals("thinking", partial.messages[1].reasoning_content)
        assert.equals('{"cmd":', partial.messages[1].tool_calls[1]["function"].arguments)
        assert.equals("actual", partial.model_name)
        assert.equals(2, #events) -- coalesced, not ten writes
        trace.messages[2] = { role = "assistant", content = "complete", usage = { completion_tokens = 3 } }
        publisher:finish_request(trace)
        local final = wait_events(events, 3)
        assert.equals(1, final.replace_from)
        assert.equals(1, #final.messages)
        assert.equals("complete", final.messages[1].content)
        assert.is_nil(final.messages[1]._partial)
        assert.equals("idle", final.status)
        assert.equals(3, final.messages[1].usage.completion_tokens)
        local reconnected = connect()
        local full = wait_events(reconnected, 1)
        assert.equals(0, full.replace_from)
        assert.equals(2, #full.messages)
        assert.equals(384, uv.fs_stat(path).mode % 512)
        trace.messages[1] = { role = "user", content = "edited history" }
        publisher:changed(trace)
        local edited = wait_events(events, 4)
        assert.equals(0, edited.replace_from)
        assert.equals("edited history", edited.messages[1].content)
    end)

    it("sends a full snapshot for a different trace and retains cancelled partial text", function()
        local trace = { start_time = 123, messages = {} }
        publisher:begin_request(trace, { body = {}, accumulated_model_response_messages = {} })
        local events = connect()
        assert.same({}, wait_events(events, 1).messages)
        local other = { start_time = 456, messages = { { role = "user", content = "other" } } }
        publisher:begin_request(other, { body = {}, accumulated_model_response_messages = { { content = "stopped" } } })
        publisher:stop(other, "cancelled")
        local event = wait_events(events, 2)
        assert.equals(0, event.replace_from)
        assert.equals("cancelled", event.status)
        assert.equals("stopped", event.messages[2].content)
        assert.is_true(event.messages[2]._partial)
        publisher:close()
        assert.is_nil(uv.fs_stat(path))
    end)

    it("drops slow readers without delaying other subscribers", function()
        local slow = { get_write_queue_size = function() return 2 * 1024 * 1024 end,
            is_closing = function() return false end, close = function(self) self.closed = true end }
        publisher.trace = { messages = {} }
        publisher.clients[slow] = {}
        publisher:send(slow, false)
        assert.is_true(slow.closed)
        assert.is_nil(publisher.clients[slow])
    end)
end)
