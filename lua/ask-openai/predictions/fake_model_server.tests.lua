require("ask-openai.helpers.test_setup").modify_package_path()
require("ask-openai.backends.curl") -- for _G.CompletionsEndpoints

local assert = require("luassert")
local describe = require("devtools.tests.describe")

local fake = require("ask-openai.predictions.fake_model_server")

--- Build a mock predictions frontend that records received SSE chunks.
---@return table frontend, table received_chunks, table state
local function create_mock_frontend()
    local received_chunks = {}
    local state = { completed = false, errors = {} }

    local frontend = {
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

describe("PredictionsFakeModelServer - chunk builders", function()
    it("content_chunk builds a valid chat-completions SSE chunk", function()
        local chunk = fake.content_chunk("def add(x, y):", "assistant")

        assert.is_table(chunk)
        assert.is_table(chunk.choices)
        assert.is_table(chunk.choices[1])
        assert.are.same("assistant", chunk.choices[1].delta.role)
        assert.are.same("def add(x, y):", chunk.choices[1].delta.content)
        assert.are.same("chat.completion.chunk", chunk.object)
        assert.is_not_nil(chunk.model)
        assert.is_not_nil(chunk.id)
    end)

    it("content_chunk defaults role to assistant", function()
        local chunk = fake.content_chunk("return x + y")
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

    it("raw_content_chunk builds a raw /completions SSE chunk", function()
        local chunk = fake.raw_content_chunk("return x", false)
        assert.are.same("return x", chunk.content)
        assert.are.same(false, chunk.stop)
    end)

    it("raw_stop_chunk marks the final raw token", function()
        local chunk = fake.raw_stop_chunk("eos")
        assert.are.same(true, chunk.stop)
        assert.are.same("eos", chunk.stop_type)
    end)
end)

describe("PredictionsFakeModelServer - install/uninstall", function()
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
end)

describe("PredictionsFakeModelServer - spawn with synchronous delivery", function()
    before_each(function()
        fake.uninstall()
        fake.reset()
        fake.clear_scripts()
        fake.set_async_delivery(false)
    end)

    after_each(function()
        fake.uninstall()
    end)

    it("delivers all scripted chunks synchronously and fires completion", function()
        fake.install()
        fake.script("test", {
            fake.content_chunk("def add(x, y):", "assistant"),
            fake.content_chunk("    return x + y"),
            fake.finish_chunk("stop"),
        })
        fake.use_script("test")

        local frontend, received_chunks, state = create_mock_frontend()
        local request = { body = {} }
        fake.spawn(request, frontend)

        assert.are.same(3, #received_chunks, "should receive 3 chunks")
        assert.is_true(state.completed, "completion should fire")
        assert.are.same(1, fake.get_request_count(), "request count should be 1")
        assert.is_true(request.body.stream, "request.body.stream should be true")

        local first = received_chunks[1]
        assert.are.same("def add(x, y):", first.choices[1].delta.content)
    end)

    it("uses a default response when no script is selected", function()
        fake.install()

        local frontend, received_chunks, state = create_mock_frontend()
        fake.spawn({ body = {} }, frontend)

        assert.are.same(2, #received_chunks, "default response should have 2 chunks")
        assert.is_true(state.completed, "completion should fire")
        local first = received_chunks[1]
        assert.are.same("    # fake default prediction", first.choices[1].delta.content)
    end)
end)

describe("PredictionsFakeModelServer - spawn with asynchronous delivery", function()
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
            fake.content_chunk("return x + y"),
            fake.finish_chunk("stop"),
        })
        fake.use_script("test")

        local frontend, received_chunks, state = create_mock_frontend()
        fake.spawn({ body = {} }, frontend)

        local ok = vim.wait(2000, function()
            return state.completed
        end, 10)

        assert.is_true(ok, "completion should fire within timeout")
        assert.are.same(2, #received_chunks, "should receive all 2 chunks")
        assert.is_true(state.completed, "completion should fire")
    end)
end)
