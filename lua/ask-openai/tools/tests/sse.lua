local curls = require("ask-openai.backends.curl_streaming")
local oai_chat = require("ask-openai.backends.oai_chat")
require("ask-openai.helpers.buffers")
local assert = require("luassert")

local function should_be_equal(expected, actual)
    assert.are.equal(expected, actual)
end

local function should_be_nil(actual)
    -- FYI you can join with _ instead of dot (.)
    --   must use this for keywords like nil, function, etc
    assert.is_nil(actual)
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
        local _, _, tool_calls_s = curls.parse_SSEs(data, oai_chat.parse_choice, "TODO-frontend", "TODO-request")
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
        local _, finish_reason, tool_calls_s = curls.parse_SSEs(data, oai_chat.parse_choice, "TODO-frontend", "TODO-request")
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

        it("on_delta, thru on_chunk, reconstitutes messages (integration test) ", function()
            -- TODO add more advanced examples (multiple tool calls, multiple message [non tool call style])
            --   IOTW index != 0 and role parsing (perhaps even group by role?)
            --
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
        end)

        local function call_on_delta(choices)
            local frontend = FakeFrontend:new()
            local request  = {}

            local deltas   = split_lines_skip_empties(choices)
            for _, delta_json in pairs(deltas) do
                local delta_table = vim.json.decode(delta_json)
                curls.on_delta(delta_table, oai_chat.parse_choice, frontend, request)
            end
            return request, frontend
        end


        it("on_delta for question (no tool calls) - ollama btw (shouldn't matter)", function()
            -- body: {"messages":[{"role":"system","content":"You are a neovim AI plugin. Your name is Neo Vim.  Please respond with markdown formatted text"},{"role":"user","content":"what is your name?"}],"model":"qwen2.5-coder:7b-instruct-q8_0","stream":true}
            -- data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"My"},"finish_reason":null}]}
            -- data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":" name"},"finish_reason":null}]}
            -- data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":" is"},"finish_reason":null}]}
            -- data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":" Neo"},"finish_reason":null}]}
            -- data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":" Vim"},"finish_reason":null}]}
            -- data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"."},"finish_reason":null}]}
            -- data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"stop"}]}
            -- data: [DONE]
            local choices = [[
                    {"index":0,"delta":{"role":"assistant","content":"My"},"finish_reason":null}
                    {"index":0,"delta":{"role":"assistant","content":" name"},"finish_reason":null}
                    {"index":0,"delta":{"role":"assistant","content":" is"},"finish_reason":null}
                    {"index":0,"delta":{"role":"assistant","content":" Neo"},"finish_reason":null}
                    {"index":0,"delta":{"role":"assistant","content":" Vim"},"finish_reason":null}
                    {"index":0,"delta":{"role":"assistant","content":"."},"finish_reason":null}
                    {"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"stop"}
            ]]

            local request = call_on_delta(choices)

            should_be_equal(1, #request.messages)
            local msg = request.messages[1]
            should_be_equal(0, msg.index)
            should_be_equal("assistant", msg.role)
            should_be_equal("My name is Neo Vim.", msg.content)

            -- TODO is finish_reason per message OR the entire request!?
            --   TODO get a multi message response to review
            should_be_equal("stop", msg.finish_reason)
        end)


        it("on_delta with two tool use requests in one message - ollama (each tool is one delta only, currently)", function()
            -- TODO can use full SSEs for parse_SSE testing/refactoring
            -- body: {"messages":[{"role":"system","content":"You are a neovim AI plugin. Your name is Neo Vim.  Please respond with markdown formatted text"},{"role":"user","content":"please list files"}],"model":"qwen2.5-coder:7b-instruct-q8_0","stream":true,"tools":[{"function":{"name":"run_command","parameters":{"properties":{"cwd":{"description":"Current working directory, leave empty in most cases","type":"string"},"command":{"description":"Command with args","type":"string"}},"required":["command"],"type":"object"}},"type":"function"},{"function":{"name":"run_script","parameters":{"properties":{"interpreter":{"description":"Command with arguments. Script will be piped to stdin. Examples: bash, fish, zsh, python, or: bash --norc","type":"string"},"script":{"description":"Script to run","type":"string"},"cwd":{"description":"Current working directory","type":"string"}},"required":["script"],"type":"object"}},"type":"function"}]}
            -- data: {"id":"chatcmpl-225","object":"chat.completion.chunk","created":1744655392,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"","tool_calls":[{"id":"call_809l7n8f","index":0,"type":"function","function":{"name":"run_command","arguments":"{\"command\":\"ls -la\"}"}}]},"finish_reason":null}]}
            -- data: {"id":"chatcmpl-225","object":"chat.completion.chunk","created":1744655393,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"","tool_calls":[{"id":"call_oqp1e2a1","index":1,"type":"function","function":{"name":"run_command","arguments":"{\"command\":\"ls -la\",\"cwd\":\"/path/to/directory\"}"}}]},"finish_reason":null}]}
            -- data: {"id":"chatcmpl-225","object":"chat.completion.chunk","created":1744655393,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"tool_calls"}]}
            -- data: [DONE]
            local choices = [[
                    {"index":0,"delta":{"role":"assistant","content":"","tool_calls":[{"id":"call_809l7n8f","index":0,"type":"function","function":{"name":"run_command","arguments":"{\"command\":\"ls -la\"}"}}]},"finish_reason":null}
                    {"index":0,"delta":{"role":"assistant","content":"","tool_calls":[{"id":"call_oqp1e2a1","index":1,"type":"function","function":{"name":"run_command","arguments":"{\"command\":\"ls -la\",\"cwd\":\"/path/to/directory\"}"}}]},"finish_reason":null}
                    {"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"tool_calls"}
            ]]

            local request, frontend = call_on_delta(choices)
            -- print("request", vim.inspect(request))
            should_be_equal(1, #request.messages)
            local msg = request.messages[1]
            should_be_equal(0, msg.index)
            should_be_equal("assistant", msg.role)
            should_be_equal("tool_calls", msg.finish_reason)
            -- tool_calls:
            should_be_equal(2, #msg.tool_calls)
            -- {"id":"call_809l7n8f","index":0,"type":"function", "function":{
            --    "name":"run_command",
            --    "arguments":"{\"command\":\"ls -la\"}"}}]},"finish_reason":null}
            first_call = msg.tool_calls[1]
            should_be_equal("call_809l7n8f", first_call.id)
            should_be_equal(0, first_call.index)
            should_be_equal("function", first_call.type)
            func = first_call["function"]
            should_be_equal("run_command", func.name)
            -- args_json = func.arguments


            -- {"id":"call_oqp1e2a1","index":1,"type":"function", "function":{
            --    "name":"run_command",
            --    "arguments":"{\"command\":\"ls -la\",\"cwd\":\"/path/to/directory\"}"}}]},"finish_reason":null}
        end)
        -- TODO add a test that validates lookup on index/role per message... need a multi message scenario (if that's ever a thing... and not multi choice... literally need two messages at same time, streaming)

        -- TODO move the vllm dual tool test here for on_delta direct testing?
    end)
end)
