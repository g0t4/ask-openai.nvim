require("ask-openai.helpers.test_setup").modify_package_path()
require("ask-openai.backends.sse.parsers")
local frontend = require("ask-openai.agents.frontend")
local SSEWrapped = require("ask-openai.agents.sse_wrapped")
local SSEDeltaWrapped = require("ask-openai.backends.sse_delta_wrapped")

describe("backend reasoning field normalization", function()
    local cases = {
        { name = "llama-server", delta = { reasoning_content = "thinking" }, expected = "thinking" },
        { name = "vLLM", delta = { reasoning = "thinking" }, expected = "thinking" },
        { name = "both fields", delta = { reasoning_content = "primary", reasoning = "fallback" }, expected = "primary" },
        { name = "empty primary", delta = { reasoning_content = "", reasoning = "fallback" }, expected = "" },
        { name = "missing fields", delta = {} },
    }
    for _, case in ipairs(cases) do
        it("normalizes " .. case.name .. " in the parser and accumulator", function()
            local choice = { index = 0, delta = vim.deepcopy(case.delta) }
            local sse = { choices = { choice } }
            local original = vim.deepcopy(sse)
            assert.equals(case.expected, SSEDeltaWrapped.new(choice.delta):reasoning())
            assert.equals(case.expected or "", parse_sse_v1_chat_completions(SSEWrapped.new(sse)).reasoning_content)
            assert.same(original, sse)
            local request = { accumulated_model_response_messages = {} }
            frontend.append_sse_to_accumulated_completion(SSEWrapped.new({ choices = { vim.deepcopy(choice) } }), request)
            local message = request.accumulated_model_response_messages[1]
            assert.equals(case.expected, message.reasoning_content)
            assert.is_nil(message.reasoning)
            assert.same(original, sse)
        end)
    end

    it("accumulates mixed field names once into reasoning_content", function()
        local request = { accumulated_model_response_messages = {} }
        for _, delta in ipairs({ { reasoning = "first " },
            { reasoning_content = "second", reasoning = "duplicate" },
            { content = "answer" } }) do
            frontend.append_sse_to_accumulated_completion(SSEWrapped.new({ choices = { { index = 0, delta = delta } } }), request)
        end
        local message = request.accumulated_model_response_messages[1]
        assert.equals("first second", message.reasoning_content)
        assert.equals("answer", message.content)
    end)

end)
