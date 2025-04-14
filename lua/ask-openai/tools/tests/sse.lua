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
    it("parses ollama all-in-one tool_calls", function()
        -- FYI! ollama might get streaming support at which point this test may become obsolete as it should split up the tool call across chunks (IIAC like vllm, and OpenAI)
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
        local _, _, tool_calls_s = curls.parse_SSEs(data, oai_chat.parse_choice, "TODO")
        should_be_equal(#tool_calls_s, 1) -- table of
        should_be_equal(#tool_calls_s[1], 1) -- table of calls
        local tool = tool_calls_s[1][1]
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
        local _, finish_reason, tool_calls_s = curls.parse_SSEs(data, oai_chat.parse_choice, "TODO")
        should_be_equal(finish_reason, "tool_calls")
        should_be_equal(#tool_calls_s, 0)
    end)

    local FakeFrontend = {}
    function FakeFrontend:new()
        -- create a table and attach methods
        local f = setmetatable({}, { __index = self })

        f.process_chunk_calls = {}
        f.process_tool_calls_calls = {}
        f.process_finish_reason_calls = {}

        -- if I make actual frontends into a class.. then I can break these out:
        --   but for now I need the closure to get to "self" which is "f" here
        --   b/c I am not calling with ":" and likely wont ever

        function f.process_chunk(chunk)
            table.insert(f.process_chunk_calls, chunk)
        end

        function f.process_tool_calls(tool_calls)
            table.insert(f.process_tool_calls_calls, tool_calls)
        end

        function f.process_finish_reason(reason)
            table.insert(f.process_finish_reason_calls, reason)
        end

        return f
    end

    describe("streaming tool_calls parses all SSEs", function()
        it("vllm capture", function()
            -- example from: https://platform.openai.com/docs/guides/function-calling?api-mode=chat#streaming
            -- indent doesn't matter for json parsing
            local events   = [[
data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}
data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"id":"chatcmpl-tool-ca99dda515524c6abe47d1ea22813507","type":"function","index":0,"function":{"name":"run_command"}}]},"logprobs":null,"finish_reason":null}]}
data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"command\": \""}}]},"logprobs":null,"finish_reason":null}]}
data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"ls"}}]},"logprobs":null,"finish_reason":null}]}
data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]},"logprobs":null,"finish_reason":null}]}
data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"content":""},"logprobs":null,"finish_reason":"tool_calls","stop_reason":null}]}
data: [DONE]
            ]]
            local frontend = FakeFrontend:new()
            local request  = {}
            local lines    = vim.split(events, "\n")
            for _, data in pairs(lines) do
                if data:match("^data: ") then
                    curls.on_chunk(data, oai_chat.parse_choice, frontend, request)
                end
            end

            should_be_equal(7, #frontend.process_tool_calls_calls) -- *** 3 layers deep actually (on_chunk/sse/tool_calls) - each sse can have 1+ tool_calls
            -- print(vim.inspect(frontend.process_tool_calls_calls))
            --
            -- *** # of tool_calls per on_chunk:
            should_be_equal(#frontend.process_tool_calls_calls[1], 0)
            should_be_equal(#frontend.process_tool_calls_calls[2], 1)
            should_be_equal(#frontend.process_tool_calls_calls[3], 1)
            should_be_equal(#frontend.process_tool_calls_calls[4], 1)
            should_be_equal(#frontend.process_tool_calls_calls[5], 1)
            should_be_equal(#frontend.process_tool_calls_calls[6], 0)
            should_be_equal(#frontend.process_tool_calls_calls[7], 0)

            -- *** first tool_calls has:
            --    id, function.name, type - only set on first tool_call for a given index
            --    index - all tool_calls have this
            --
            -- [{"id":"chatcmpl-tool-ca99dda515524c6abe47d1ea22813507","type":"function","index":0,
            --     "function":{"name":"run_command"}}]
            second = frontend.process_tool_calls_calls[2]
            -- print("second", vim.inspect(second))
            second_only_tool_call = second[1]
            should_be_equal(0, second_only_tool_call.index)
            should_be_equal("chatcmpl-tool-ca99dda515524c6abe47d1ea22813507", second_only_tool_call.id)
            should_be_equal("function", second_only_tool_call.type)
            func = second_only_tool_call["function"]
            should_be_equal("run_command", func.name)

            -- *** 2nd + tool_calls have index and function.arguments (deltas)
            -- [{"index":0,"function":{"arguments":"{\"command\": \""}}]
            third = frontend.process_tool_calls_calls[3]
            third_only_tool_call = third[1]
            should_be_equal(0, third_only_tool_call.index)
            func_args = third_only_tool_call["function"]["arguments"]
            should_be_equal("{\"command\": \"", func_args)

            -- [{"index":0,"function":{"arguments":"ls"}}]
            fourth = frontend.process_tool_calls_calls[4]
            fourth_only_tool_call = fourth[1]
            should_be_equal(0, fourth_only_tool_call.index)
            func_args = fourth_only_tool_call["function"]["arguments"]
            should_be_equal("ls", func_args)

            -- [{"index":0,"function":{"arguments":"\"}"}}]
            fifth = frontend.process_tool_calls_calls[5]
            fifth_only_tool_call = fifth[1]
            should_be_equal(0, fifth_only_tool_call.index)
            func_args = fifth_only_tool_call["function"]["arguments"]
            should_be_equal("\"}", func_args)

            -- TODO test aggregated function.arguments
            -- function.arguments is aggregated across all deltas, just like content, into one string (serialized json for args)

            -- is it possible for other fields like function.name to be split up too (deltas)?
            --    I do not believe this is possible but it could fit the mold of function.arguments
        end)
        -- TODO capture and test a double tool_call
        --  IIAC index will be 0 and 1?

        -- it("full tool_call parses", function()
        --     -- example from: https://platform.openai.com/docs/guides/function-calling?api-mode=chat#streaming
        --     -- indent doesn't matter for json parsing
        --     -- local events = [[
        --     --     [{"index": 0, "id": "call_DdmO9pD3xa9XTPNJ32zg2hcA", "function": {"arguments": "", "name": "get_weather"}, "type": "function"}]
        --     --     [{"index": 0, "id": null, "function": {"arguments": "{\"", "name": null}, "type": null}]
        --     --     [{"index": 0, "id": null, "function": {"arguments": "location", "name": null}, "type": null}]
        --     --     [{"index": 0, "id": null, "function": {"arguments": "\":\"", "name": null}, "type": null}]
        --     --     [{"index": 0, "id": null, "function": {"arguments": "Paris", "name": null}, "type": null}]
        --     --     [{"index": 0, "id": null, "function": {"arguments": ",", "name": null}, "type": null}]
        --     --     [{"index": 0, "id": null, "function": {"arguments": " France", "name": null}, "type": null}]
        --     --     [{"index": 0, "id": null, "function": {"arguments": "\"}", "name": null}, "type": null}]
        --     --     null
        --     -- ]]
        --     -- ok I think the last null means the last SSE has `tool_calls: null`
        --     -- actually lets wait to get a real sample... the above is NOT the full SSE... darnit
        -- end)
    end)
end)
