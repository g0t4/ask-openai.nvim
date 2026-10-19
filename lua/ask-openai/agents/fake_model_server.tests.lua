require("ask-openai.helpers.test_setup").modify_package_path()
require("ask-openai.backends.curl") -- for _G.CompletionsEndpoints

local assert = require("luassert")
local describe = require("devtools.tests.describe")

local fake = require("ask-openai.agents.fake_model_server")
local CurlRequestForTrace = require("ask-openai.agents.curl_request_for_trace")
local AgentTrace = require("ask-openai.agents.trace")

--- Build a mock frontend that records received SSE chunks and completion state.
---@param trace? AgentTrace
---@return table frontend, table received_chunks, table state
local function create_mock_frontend(trace)
    local received_chunks = {}
    local state = { completed = false, errors = {} }

    local frontend = {
        trace = trace,
        on_parsed_data_sse = function(chunk)
            table.insert(received_chunks, chunk)
        end,
        on_curl_exited_successfully = function()
            state.completed = true
        end,
        explain_error = function(msg)
            table.insert(state.errors, msg)
        end,
    }
    return frontend, received_chunks, state
end

--- Create a fresh AgentTrace with the given messages.
---@param messages? table[]
---@return AgentTrace
local function create_trace(messages)
    return AgentTrace:new({ messages = messages or {} }, "http://localhost:8080")
end

--- Build a finish chunk with default timings so last_sse is set on the rx_message.
---@param finish_reason? string
---@return table
local function finish_chunk_with_timings(finish_reason)
    return fake.finish_chunk(finish_reason or "stop", {
        prompt_n = 10,
        predicted_n = 5,
        prompt_per_second = 100,
        predicted_per_second = 50,
        cache_n = 0,
    })
end

-- ****************************************************************************
-- * PART A: fixture self-tests.
-- * These exercise the fake_model_server test double itself (its chunk
-- * builders, install/uninstall of curl.spawn, delivery mechanics, and script
-- * bookkeeping) rather than the real agent code.
-- ****************************************************************************
describe("FakeModelServer - chunk builders", function()
    it("content_chunk builds a valid SSE chunk", function()
        local chunk = fake.content_chunk("Hello", "assistant")

        assert.is_table(chunk)
        assert.is_table(chunk.choices)
        assert.is_table(chunk.choices[1])
        assert.are.same("assistant", chunk.choices[1].delta.role)
        assert.are.same("Hello", chunk.choices[1].delta.content)
        assert.are.same("chat.completion.chunk", chunk.object)
        assert.is_not_nil(chunk.model)
        assert.is_not_nil(chunk.id)
        assert.is_not_nil(chunk.created)
    end)

    it("content_chunk defaults role to assistant", function()
        local chunk = fake.content_chunk("Hello")
        assert.are.same("assistant", chunk.choices[1].delta.role)
    end)

    it("reasoning_chunk builds a reasoning SSE chunk", function()
        local chunk = fake.reasoning_chunk("thinking...")
        assert.are.same("thinking...", chunk.choices[1].delta.reasoning_content)
        assert.are.same("assistant", chunk.choices[1].delta.role)
    end)

    it("finish_chunk builds a finish_reason chunk", function()
        local chunk = fake.finish_chunk("stop")
        assert.are.same("stop", chunk.choices[1].finish_reason)
        assert.are.same({}, chunk.choices[1].delta)
    end)

    it("finish_chunk defaults to stop", function()
        local chunk = fake.finish_chunk()
        assert.are.same("stop", chunk.choices[1].finish_reason)
    end)

    it("tool_call_chunk builds a tool call SSE chunk", function()
        local chunk = fake.tool_call_chunk({
            id = "call_123",
            name = "run_bash",
            arguments = '{"cmd":"date"}',
        })

        local tool_call = chunk.choices[1].delta.tool_calls[1]
        assert.are.same("call_123", tool_call.id)
        assert.are.same("function", tool_call.type)
        assert.are.same("run_bash", tool_call["function"].name)
        assert.are.same('{"cmd":"date"}', tool_call["function"].arguments)
    end)

    it("tool_call_args_chunk builds a tool call argument continuation", function()
        local chunk = fake.tool_call_args_chunk('{"cmd":"', 0)

        local tool_call = chunk.choices[1].delta.tool_calls[1]
        assert.are.same('{"cmd":"', tool_call["function"].arguments)
        assert.are.same(0, tool_call.index)
    end)
end)

describe("FakeModelServer - install/uninstall", function()
    before_each(function()
        fake.uninstall()
        fake.reset()
        fake.clear_scripts()
    end)

    it("installs and replaces curl.spawn", function()
        local curl = require("ask-openai.backends.curl")
        local original_spawn = curl.spawn

        fake.install()
        assert.is_true(fake.is_installed())
        assert.are.equal(fake.spawn, curl.spawn, "curl.spawn should be replaced")
        assert.are.equal(original_spawn, fake._original_spawn, "original spawn should be saved")
    end)

    it("uninstall restores curl.spawn", function()
        local curl = require("ask-openai.backends.curl")
        local original_spawn = curl.spawn

        fake.install()
        fake.uninstall()

        assert.is_false(fake.is_installed())
        assert.are.equal(original_spawn, curl.spawn, "curl.spawn should be restored")
    end)

    it("install is idempotent", function()
        fake.install()
        fake.install()
        assert.is_true(fake.is_installed())
        assert.are.equal(fake.spawn, require("ask-openai.backends.curl").spawn)
    end)

    it("uninstall when not installed is a no-op", function()
        fake.uninstall()
        assert.is_false(fake.is_installed())
    end)
end)

describe("FakeModelServer - spawn with synchronous delivery", function()
    before_each(function()
        fake.uninstall()
        fake.reset()
        fake.clear_scripts()
        fake.set_async_delivery(false)
    end)

    after_each(function()
        fake.uninstall()
    end)

    it("delivers all scripted chunks synchronously", function()
        fake.install()
        fake.script("test", {
            fake.content_chunk("Hello", "assistant"),
            fake.content_chunk(" world"),
            fake.finish_chunk("stop"),
        })
        fake.use_script("test")

        local trace = create_trace()
        local frontend, received_chunks, state = create_mock_frontend(trace)

        local request = CurlRequestForTrace:new({
            body = { messages = {} },
            base_url = "http://localhost:8080",
            endpoint = _G.CompletionsEndpoints.v1_chat_completions,
            type = "agents",
        })

        fake.spawn(request, frontend)

        assert.are.same(3, #received_chunks, "should receive 3 chunks")
        assert.is_true(state.completed, "completion should fire")
        assert.are.same(1, fake.get_request_count(), "request count should be 1")
        assert.is_true(request.body.stream, "request.body.stream should be true")
        assert.are.equal(request, trace.last_request, "trace.last_request should be set")
    end)

    it("uses default greeting when no script is selected", function()
        fake.install()

        local trace = create_trace()
        local frontend, received_chunks, state = create_mock_frontend(trace)

        local request = CurlRequestForTrace:new({
            body = { messages = {} },
            base_url = "http://localhost:8080",
            endpoint = _G.CompletionsEndpoints.v1_chat_completions,
            type = "agents",
        })

        fake.spawn(request, frontend)

        assert.are.same(2, #received_chunks, "default response should have 2 chunks")
        assert.is_true(state.completed, "completion should fire")
        local first = received_chunks[1]
        assert.are.same("Hello from fake model server!", first.choices[1].delta.content)
    end)

    it("delivers tool call chunks in order", function()
        fake.install()
        fake.script("tool_call", {
            fake.tool_call_chunk({
                id = "call_1",
                name = "run_bash",
                arguments = '{"cmd":',
            }),
            fake.tool_call_args_chunk('"date"}', 0),
            fake.finish_chunk("tool_calls"),
        })
        fake.use_script("tool_call")

        local trace = create_trace()
        local frontend, received_chunks, state = create_mock_frontend(trace)

        local request = CurlRequestForTrace:new({
            body = { messages = {} },
            base_url = "http://localhost:8080",
            endpoint = _G.CompletionsEndpoints.v1_chat_completions,
            type = "agents",
        })

        fake.spawn(request, frontend)

        assert.are.same(3, #received_chunks, "should receive 3 chunks")
        assert.is_true(state.completed, "completion should fire")

        local first_chunk = received_chunks[1]
        local tool_call_delta = first_chunk.choices[1].delta.tool_calls[1]
        assert.are.same("call_1", tool_call_delta.id)
        assert.are.same("run_bash", tool_call_delta["function"].name)
    end)

    it("invokes on_request_started hook before delivering chunks", function()
        fake.install()
        fake.script("test", { fake.content_chunk("Hi") })
        fake.use_script("test")

        local hook_called = false
        local hook_request = nil
        fake.set_on_request_started(function(req)
            hook_called = true
            hook_request = req
        end)

        local trace = create_trace()
        local frontend = create_mock_frontend(trace)

        local request = CurlRequestForTrace:new({
            body = { messages = {} },
            base_url = "http://localhost:8080",
            endpoint = _G.CompletionsEndpoints.v1_chat_completions,
            type = "agents",
        })

        fake.spawn(request, frontend)

        assert.is_true(hook_called, "on_request_started should be called")
        assert.are.equal(request, hook_request)
    end)

    it("invokes on_request_completed hook after all chunks delivered", function()
        fake.install()
        fake.script("test", {
            fake.content_chunk("Hi"),
            fake.finish_chunk("stop"),
        })
        fake.use_script("test")

        local completed_hook_called = false
        local completed_hook_request = nil
        fake.set_on_request_completed(function(req)
            completed_hook_called = true
            completed_hook_request = req
        end)

        local trace = create_trace()
        local frontend = create_mock_frontend(trace)

        local request = CurlRequestForTrace:new({
            body = { messages = {} },
            base_url = "http://localhost:8080",
            endpoint = _G.CompletionsEndpoints.v1_chat_completions,
            type = "agents",
        })

        fake.spawn(request, frontend)

        assert.is_true(completed_hook_called, "on_request_completed should be called")
        assert.are.equal(request, completed_hook_request)
    end)
end)

describe("FakeModelServer - spawn with asynchronous delivery", function()
    before_each(function()
        fake.uninstall()
        fake.reset()
        fake.clear_scripts()
        fake.set_async_delivery(true)
        fake.set_chunk_delay_ms(1)
    end)

    after_each(function()
        fake.uninstall()
    end)

    it("delivers all chunks asynchronously and fires completion", function()
        fake.install()
        fake.script("test", {
            fake.content_chunk("Hello", "assistant"),
            fake.content_chunk(" world"),
            fake.finish_chunk("stop"),
        })
        fake.use_script("test")

        local trace = create_trace()
        local frontend, received_chunks, state = create_mock_frontend(trace)

        local request = CurlRequestForTrace:new({
            body = { messages = {} },
            base_url = "http://localhost:8080",
            endpoint = _G.CompletionsEndpoints.v1_chat_completions,
            type = "agents",
        })

        fake.spawn(request, frontend)

        -- Wait for async delivery
        local ok = vim.wait(2000, function()
            return state.completed
        end, 10)

        assert.is_true(ok, "completion should fire within timeout")
        assert.are.same(3, #received_chunks, "should receive all 3 chunks")
        assert.is_true(state.completed, "completion should fire")
        assert.are.equal(request, trace.last_request, "trace.last_request should be set")
    end)
end)

describe("FakeModelServer - script management", function()
    before_each(function()
        fake.reset()
        fake.clear_scripts()
    end)

    it("script() stores and use_script() selects", function()
        fake.script("my_script", { fake.content_chunk("hi") })
        fake.use_script("my_script")

        local scripts = fake.get_scripts()
        assert.is_table(scripts["my_script"])
        assert.are.same(1, #scripts["my_script"])
    end)

    it("clear_scripts() empties the script table", function()
        fake.script("a", { fake.content_chunk("hi") })
        fake.clear_scripts()

        assert.are.same({}, fake.get_scripts())
    end)

    it("reset() clears state", function()
        fake.script("a", { fake.content_chunk("hi") })
        fake.use_script("a")
        fake.spawn({ body = {} }, {})
        fake.reset()

        assert.are.same(0, fake.get_request_count())
    end)
end)

--- Create a mock chat window with a real Neovim buffer backing it.
---@return table chat_window
local function create_mock_chat_window()
    local bufnr = vim.api.nvim_create_buf(false, true)

    local buffer = {
        buffer_number = bufnr,
        folds = {},
        get_line_count = function(self)
            return vim.api.nvim_buf_line_count(bufnr)
        end,
        get_lines_from = function(self, line_number_0indexed)
            local lines = vim.api.nvim_buf_get_lines(bufnr, line_number_0indexed, -1, false)
            return table.concat(lines, "\n")
        end,
        append_styled_lines = function(self, lines)
            local text_lines = lines.turn_lines or {}
            vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, text_lines)
        end,
        replace_with_styled_lines_after = function(self, start_line_base0, lines)
            local text_lines = lines.turn_lines or {}
            -- Clear from start_line_base0 to end, then append
            local existing = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local keep = {}
            for i = 1, math.min(start_line_base0, #existing) do
                table.insert(keep, existing[i])
            end
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, keep)
            vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, text_lines)
        end,
        clear = function()
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
        end,
    }

    local chat_window = {
        buffer_number = bufnr,
        buffer = buffer,
        _agent_is_running = false,
        _footer = nil,
        mark_agent_running = function(self, value)
            self._agent_is_running = value
        end,
        stop_spinner = function(self, final_title)
            self._agent_is_running = false
            self._footer = final_title
        end,
        ensure_spinner_running = function() end,
        explain_error = function() end,
        clear = function()
            buffer:clear()
        end,
        close = function() end,
        open = function() end,
        rebuild_title = function() end,
        resize = function() end,
        set_token_count = function() end,
        update_model_name = function() end,
        append_styled_lines = function(self, lines)
            buffer:append_styled_lines(lines)
        end,
    }

    return chat_window
end

-- ****************************************************************************
-- * PART B: real integration tests.
-- * These drive the actual agent code paths (frontend.then_get_assistant_response,
-- * AgentTrace accumulation, SSE parsing, tool router, queued messages) with the
-- * fake server injected in place of curl.spawn.
-- ****************************************************************************
describe("FakeModelServer - AgentsFrontend integration", function()
    local frontend

    before_each(function()
        fake.uninstall()
        fake.reset()
        fake.clear_scripts()
        fake.set_async_delivery(false)
        fake.set_chunk_delay_ms(1)
        -- Set model name to match configured model to avoid mismatch warnings
        local config = require("ask-openai.config")
        fake.set_model_name(config.get_agents_model() or "fake-model")

        -- Load AgentsFrontend and set up mock state
        frontend = require("ask-openai.agents.frontend")
        frontend.chat_window = create_mock_chat_window()
        frontend.user_input_window = nil
        frontend.queued_messages = {}
        frontend.trace = nil
        frontend.current_turn_start_line_base0 = nil
        frontend.queued_section_start_line_base0 = nil

        -- Mock ensure_user_input_window_is_open to avoid creating real float windows
        frontend.ensure_user_input_window_is_open = function() end

        fake.install()
    end)

    after_each(function()
        fake.uninstall()

        -- Give pending vim.schedule callbacks a chance to finish before cleanup
        -- (update_ui_chat_viewer and on_curl_exited_successfully use vim.schedule)
        vim.wait(500)

        if frontend.chat_window and frontend.chat_window.buffer
            and frontend.chat_window.buffer.buffer_number then
            pcall(vim.api.nvim_buf_delete, frontend.chat_window.buffer.buffer_number, { force = true })
        end

        frontend.chat_window = nil
        frontend.trace = nil
        frontend.queued_messages = {}
    end)

    it("streams a simple content response into the trace", function()
        fake.script("simple", {
            fake.content_chunk("Hello from the agent!", "assistant"),
            finish_chunk_with_timings("stop"),
        })
        fake.use_script("simple")

        local trace = create_trace({})
        frontend.trace = trace

        -- Trigger a request via the frontend
        frontend.then_get_assistant_response(trace)

        -- Wait for async completion (on_curl_exited_successfully uses vim.schedule)
        local ok = vim.wait(1000, function()
            return trace.last_request
                and trace.last_request.accumulated_model_response_messages
                and #trace.last_request.accumulated_model_response_messages > 0
        end, 10)

        assert.is_true(ok, "should receive accumulated response")

        local request = trace.last_request
        assert.is_not_nil(request, "last_request should be set")
        assert.are.same(1, #request.accumulated_model_response_messages)

        local rx_message = request.accumulated_model_response_messages[1]
        assert.are.same("assistant", rx_message.role)
        assert.are.same("Hello from the agent!", rx_message.content)
        assert.are.same("stop", rx_message.finish_reason)

        -- * wes testing
        vim.wait(1) -- defer to make sure buffer is updated (vim.schedule/defer_fn calls inside of handlers)
        -- without wait, buffer will be empty as there's been no updates to it yet
        vim.print(frontend.chat_window.buffer:get_lines_from(0))
    end)

    it("accumulates reasoning content separately", function()
        fake.script("reasoning", {
            fake.reasoning_chunk("Let me think...", "assistant"),
            fake.content_chunk("The answer is 42.", "assistant"),
            finish_chunk_with_timings("stop"),
        })
        fake.use_script("reasoning")

        local trace = create_trace({})
        frontend.trace = trace

        frontend.then_get_assistant_response(trace)

        local ok = vim.wait(1000, function()
            return trace.last_request
                and trace.last_request.accumulated_model_response_messages
                and #trace.last_request.accumulated_model_response_messages > 0
        end, 10)

        assert.is_true(ok, "should receive accumulated response")

        local rx_message = trace.last_request.accumulated_model_response_messages[1]
        assert.are.same("Let me think...", rx_message.reasoning_content)
        assert.are.same("The answer is 42.", rx_message.content)
    end)

    it("parses tool calls from streamed SSE chunks", function()
        fake.script("tool_calls", {
            fake.tool_call_chunk({
                id = "call_abc",
                name = "run_bash",
                arguments = '{"cmd":',
            }),
            fake.tool_call_args_chunk('"date"}', 0),
            finish_chunk_with_timings("tool_calls"),
        })
        fake.use_script("tool_calls")

        local trace = create_trace({})
        frontend.trace = trace

        frontend.then_get_assistant_response(trace)

        local ok = vim.wait(1000, function()
            return trace.last_request
                and trace.last_request.accumulated_model_response_messages
                and #trace.last_request.accumulated_model_response_messages > 0
        end, 10)

        assert.is_true(ok, "should receive accumulated response")

        local rx_message = trace.last_request.accumulated_model_response_messages[1]
        assert.are.same(1, #rx_message.tool_calls, "should have 1 tool call")

        local tool_call = rx_message.tool_calls[1]
        assert.are.same("call_abc", tool_call.id)
        assert.are.same("run_bash", tool_call["function"].name)
        assert.are.same('{"cmd":"date"}', tool_call["function"].arguments)
    end)

    it("adds assistant message to trace after completion", function()
        fake.script("response", {
            fake.content_chunk("Final answer", "assistant"),
            finish_chunk_with_timings("stop"),
        })
        fake.use_script("response")

        local trace = create_trace({})
        frontend.trace = trace

        frontend.then_get_assistant_response(trace)

        -- Wait for on_curl_exited_successfully to run (it uses vim.schedule)
        local ok = vim.wait(1000, function()
            return #trace.messages > 0
        end, 10)

        assert.is_true(ok, "trace should have messages after completion")
        assert.are.same(1, #trace.messages)
        assert.are.same("assistant", trace.messages[1].role)
        assert.are.same("Final answer", trace.messages[1].content)
    end)

    it("stops agent running state after final message", function()
        fake.script("response", {
            fake.content_chunk("Done", "assistant"),
            finish_chunk_with_timings("stop"),
        })
        fake.use_script("response")

        local trace = create_trace({})
        frontend.trace = trace

        frontend.chat_window:mark_agent_running(true)
        frontend.then_get_assistant_response(trace)

        local ok = vim.wait(1000, function()
            return not frontend.chat_window._agent_is_running
        end, 10)

        assert.is_true(ok, "agent should stop running after final message")
        assert.is_false(frontend.chat_window._agent_is_running)
    end)

    it("delivers queued messages after the agent finishes a final message", function()
        fake.script("response", {
            fake.content_chunk("Done", "assistant"),
            finish_chunk_with_timings("stop"),
        })
        fake.use_script("response")

        local trace = create_trace({})
        frontend.trace = trace

        -- Queue a user message while the agent is running
        local TxChatMessage = require("ask-openai.agents.messages.tx")
        local queued = TxChatMessage:user("remember to mention the year")
        table.insert(frontend.queued_messages, queued)

        frontend.then_get_assistant_response(trace)

        -- Wait for the final message to be processed and queued message delivered
        local ok = vim.wait(2000, function()
            return #trace.messages >= 2
        end, 10)

        assert.is_true(ok, "queued message should be delivered after final message")
        assert.are.same("assistant", trace.messages[1].role)
        assert.are.same("Done", trace.messages[1].content)

        -- The queued message should have been delivered and then a follow-up request sent.
        -- Since the fake server re-uses the same script ("response"), the follow-up
        -- also produces "Done", so we'll see: assistant, user, assistant.
        assert.are.same("user", trace.messages[2].role)
        assert.are.same("remember to mention the year", trace.messages[2].content)

        -- Wait for the follow-up request to complete too
        vim.wait(2000, function()
            return #trace.messages >= 3
        end, 10)

        assert.are.same(3, #trace.messages)
        assert.are.same("assistant", trace.messages[3].role)
        assert.are.same(0, #frontend.queued_messages, "queue should be drained")
    end)

    it("runs tools after tool_calls finish_reason", function()
        -- Mock the tool router to avoid real tool execution
        local tool_router = require("ask-openai.tools.router")
        local original_send_tool_call_router = tool_router.send_tool_call_router
        tool_router.send_tool_call_router = function(tool_call, callback, on_progress)
            -- Simulate a tool completing with a simple result
            local ToolCallOutput = require("ask-openai.agents.tools.tool_call_output")
            local result = {
                content = "Tool result: date output",
                isError = false,
            }
            callback(result)
            return function() end
        end

        fake.script("tool_flow", {
            fake.tool_call_chunk({
                id = "call_1",
                name = "run_bash",
                arguments = '{"cmd":"date"}',
            }),
            finish_chunk_with_timings("tool_calls"),
        })
        fake.script("tool_followup", {
            fake.content_chunk("Today's date is available", "assistant"),
            finish_chunk_with_timings("stop"),
        })

        -- Set initial script before triggering the request
        fake.use_script("tool_flow")

        -- First request uses "tool_flow" script; subsequent requests use "tool_followup"
        local request_count = 0
        fake.set_on_request_started(function()
            request_count = request_count + 1
            if request_count > 1 then
                fake.use_script("tool_followup")
            end
        end)

        local trace = create_trace({})
        frontend.trace = trace

        frontend.then_get_assistant_response(trace)

        -- Wait for the tool to complete and the next response to arrive
        local ok = vim.wait(2000, function()
            return #trace.messages >= 3
        end, 10)

        tool_router.send_tool_call_router = original_send_tool_call_router
        fake.set_on_request_started(nil)

        assert.is_true(ok, "tool results should be sent back and agent should respond")

        -- Verify the tool result message was added to the trace
        local has_tool_result = false
        for _, msg in ipairs(trace.messages) do
            if msg.role == "tool" then
                has_tool_result = true
                assert.are.same("call_1", msg.tool_call_id)
                break
            end
        end
        assert.is_true(has_tool_result, "tool result should be in trace messages")

        -- Verify final assistant response
        local last_message = trace.messages[#trace.messages]
        assert.are.same("assistant", last_message.role)
        assert.are.same("Today's date is available", last_message.content)
    end)

    it("shows queued messages pinned to the bottom of the chat window", function()
        local TxChatMessage = require("ask-openai.agents.messages.tx")
        local queued = TxChatMessage:user("queued message")
        table.insert(frontend.queued_messages, queued)

        frontend.redraw_queued_messages()

        local bufnr = frontend.chat_window.buffer_number
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local text = table.concat(lines, "\n")

        assert.is_true(text:find("queued message", 1, true) ~= nil,
            "queued message should appear in chat window. Got: " .. text)
        assert.is_not_nil(frontend.queued_section_start_line_base0,
            "queued_section_start_line_base0 should be set")
    end)
end)
