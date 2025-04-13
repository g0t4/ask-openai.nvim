local curls = require("ask-openai.backends.curl_streaming")
local oai_chat = require("ask-openai.backends.oai_chat")
local assert = require("luassert")

-- PRN move this to backends dir and consolidate all tests there?
-- ***! use <leader>u to run tests in this file! (habituate that, don't type out the cmd yourself)

describe("tool use SSE parsing in /v1/chat/completions", function()
    it("parses ollama tool_calls - all in one SSE", function()
        -- *** escape SSE log outputs: \" => \\"    (only backslashes, not " b/c you are putting this inside a ' single quote)
        local sse =
        'data: {"id":"chatcmpl-304","object":"chat.completion.chunk","created":1744521962,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"","tool_calls":[{"id":"call_lbcjwr0u","index":0,"type":"function","function":{"name":"run_command","arguments":"{\\"command\\":\\"ls -a\\"}"}}]},"finish_reason":null}]}'
        -- "choices":[
        --   {"index":0,"delta":
        --     {"role":"assistant","content":"","tool_calls":
        --       [{
        --         "id":"call_lbcjwr0u","index":0,"type":"function",
        --         "function": {
        --           "name":"run_command",
        --           "arguments":"{\"command\":\"ls -a\"}"
        --         }
        --       }]
        --     },
        --     "finish_reason":null
        --   }]
        local chunk, _, tool_calls = curls.sse_to_chunk(sse, oai_chat.parse_choice)
        assert.are.equal(#tool_calls, 1)
        local tool = tool_calls[1]
        assert.are.equal(tool.id, "call_lbcjwr0u")
        assert.are.equal(tool.index, 0)
        assert.are.equal(tool.type, "function")
        func = tool["function"]
        assert.are.equal(type(func), "table")
        assert.are.equal(func.name, "run_command")
        assert.are.equal(func.arguments, '{"command":"ls -a"}')
    end)
    -- it("", function()
    --     -- data: {"id":"chatcmpl-304","object":"chat.completion.chunk","created":1744521962,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"tool_calls"}]}
    -- end)
    -- it("", function()
    -- end)
end)
