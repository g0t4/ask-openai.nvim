require("ask-openai.helpers.test_setup").modify_package_path()
local response_reasoning = require("ask-openai.backends.response_reasoning")
require("ask-openai.backends.sse.parsers")
local frontend = require("ask-openai.agents.frontend")

describe("backend reasoning field normalization", function()
    local cases = {
        { name = "llama-server", delta = { reasoning_content = "thinking" }, expected = "thinking" },
        { name = "vLLM", delta = { reasoning = "thinking" }, expected = "thinking" },
        { name = "null primary", delta = { reasoning_content = vim.NIL, reasoning = "thinking" }, expected = "thinking" },
        { name = "both fields", delta = { reasoning_content = "primary", reasoning = "fallback" }, expected = "primary" },
        { name = "empty primary", delta = { reasoning_content = "", reasoning = "fallback" }, expected = "" },
        { name = "missing fields", delta = {} },
        { name = "null fields", delta = { reasoning_content = vim.NIL, reasoning = vim.NIL } },
    }
    for _, case in ipairs(cases) do
        it("normalizes " .. case.name .. " in the parser and accumulator", function()
            local choice = { index = 0, delta = vim.deepcopy(case.delta) }
            local sse = { choices = { choice } }
            local original = vim.deepcopy(sse)
            assert.equals(case.expected, response_reasoning.get_content(choice.delta))
            assert.equals(case.expected or "", parse_sse_v1_chat_completions(sse).reasoning_content)
            assert.same(original, sse)
            local request = { accumulated_model_response_messages = {} }
            frontend.on_streaming_delta_update_message_history(vim.deepcopy(choice), request, sse)
            local message = request.accumulated_model_response_messages[1]
            assert.equals(case.expected, message.reasoning_content)
            assert.is_nil(message.reasoning)
            assert.same(original, sse)
        end)
    end

    it("accumulates mixed field names once into reasoning_content", function()
        local request = { accumulated_model_response_messages = {} }
        for _, delta in ipairs({ { reasoning = "first " },
            { reasoning_content = vim.NIL, reasoning = "second " },
            { reasoning_content = "third", reasoning = "duplicate" },
            { content = "answer" } }) do
            frontend.on_streaming_delta_update_message_history({ index = 0, delta = delta }, request, {})
        end
        local message = request.accumulated_model_response_messages[1]
        assert.equals("first second third", message.reasoning_content)
        assert.equals("answer", message.content)
    end)
    it("ignores SGLang's metadata-only SSEs in the text parser", function()
        for _, sse in ipairs({ { choices = {}, usage = { completion_tokens = 3 } },
            { choices = {}, sglext = { spec_tokens_details = {} } } }) do
            local parsed = parse_sse_v1_chat_completions(sse)
            assert.equals("", parsed.content)
            assert.equals("", parsed.reasoning_content)
            assert.is_false(parsed.done)
        end
    end)

end)
