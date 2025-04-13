local curls = require("ask-openai.backends.curl_streaming")
local oai_chat = require("ask-openai.backends.oai_chat")
local assert = require("luassert")

local function should_be_equal(t1, t2)
    assert.are.equal(t1, t2)
end

local function should_be_nil(t)
    -- FYI you can join with _ instead of dot (.)
    --   must use this for keywords like nil, function, etc
    assert.is_nil(t)
end

-- PRN move this to backends dir and consolidate all tests there?
-- ***! use <leader>u to run tests in this file! (habituate that, don't type out the cmd yourself)

describe("tool use SSE parsing in /v1/chat/completions", function()
    it("parses ollama tool_calls", function()
        -- *** escape SSE log outputs: \" => \\"    (only backslashes, not " b/c you are putting this inside a ' single quote)
        local data =
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
        local _, _, tool_calls = curls.sse_to_chunk(data, oai_chat.parse_choice)
        should_be_equal(#tool_calls, 1)
        local tool = tool_calls[1]
        should_be_equal(tool.id, "call_lbcjwr0u")
        should_be_equal(tool.index, 0)
        should_be_equal(tool.type, "function")
        func = tool["function"]
        should_be_equal(type(func), "table")
        should_be_equal(func.name, "run_command")
        should_be_equal(func.arguments, '{"command":"ls -a"}')
        -- TODO leave arguments as serialized json as it'll be passed as is to MCP (IIRC)
    end)

    it("parses ollama finish_reason", function()
        local data =
        'data: {"id":"chatcmpl-304","object":"chat.completion.chunk","created":1744521962,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"tool_calls"}]}'
        local _, finish_reason, tool_calls = curls.sse_to_chunk(data, oai_chat.parse_choice)
        should_be_equal(finish_reason, "tool_calls")
        should_be_nil(tool_calls)
    end)

    -- it("", function()
    -- end)
end)
