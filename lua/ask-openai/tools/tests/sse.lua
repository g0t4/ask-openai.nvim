local curls = require("ask-openai.backends.curl_streaming")
local oai_chat = require("ask-openai.backends.oai_chat")
local text = require("ask-openai.helpers.text")
require("ask-openai.helpers.buffers")
local test_setup = require("ask-openai.helpers.test_setup")
test_setup.modify_package_path()

local should = require("devtools.tests.should")

-- PRN move this to backends dir and consolidate all tests there?
-- ***! use <leader>u to run tests in this file! (habituate that, don't type out the cmd yourself)

describe("tool use SSE parsing in /v1/chat/completions", function()
    local FakeFrontend = {}
    function FakeFrontend:new()
        -- create a table and attach methods
        local f = setmetatable({}, { __index = self })

        f.on_generated_text_calls = {}
        f.process_finish_reason_calls = {}

        -- if I make actual frontends into a class.. then I can break these out:
        --   but for now I need the closure to get to "self" which is "f" here
        --   b/c I am not calling with ":" and likely wont ever

        function f.on_generated_text(chunk)
            table.insert(f.on_generated_text_calls, chunk)
        end

        function f.process_finish_reason(reason)
            table.insert(f.process_finish_reason_calls, reason)
        end

        function f.handle_messages_updated()
        end

        function f.on_sse_llama_server_timings(parsed)
        end

        function f.on_sse_llama_server_error_explanation(error)
        end

        return f
    end

    describe("streaming tool_calls parses all SSEs", function()
        it("on_delta, thru on_chunk, reconstitutes messages (integration test) ", function()
            -- TODO add more advanced examples (multiple tool calls, multiple message [non tool call style])
            --   IOTW index != 0 and role parsing (perhaps even group by role?)
            --
            local events = [[
data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}
data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"id":"chatcmpl-tool-ca99dda515524c6abe47d1ea22813507","type":"function","index":0,"function":{"name":"run_command"}}]},"logprobs":null,"finish_reason":null}]}
data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"command\": \""}}]},"logprobs":null,"finish_reason":null}]}
data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"ls"}}]},"logprobs":null,"finish_reason":null}]}
data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]},"logprobs":null,"finish_reason":null}]}
data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"content":""},"logprobs":null,"finish_reason":"tool_calls","stop_reason":null}]}
data: [DONE]
            ]]
            local frontend = FakeFrontend:new()
            local request = {}
        end)

        local function call_on_delta(choices)
            local frontend = FakeFrontend:new()
            local request = {}

            local deltas = text.split_lines_skip_empties(choices)
            for _, delta_json in pairs(deltas) do
                local delta_table = vim.json.decode(delta_json)
                curls.on_delta_update_message_history(delta_table, request)
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

            should.be_equal(1, #request.messages)
            local msg = request.messages[1]
            should.be_equal(0, msg.index)
            should.be_equal("assistant", msg.role)
            should.be_equal("My name is Neo Vim.", msg.content)

            -- TODO is finish_reason per message OR the entire request!?
            --   TODO get a multi message response to review
            should.be_equal("stop", msg.finish_reason)
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
            should.be_equal(1, #request.messages)
            local msg = request.messages[1]
            should.be_equal(0, msg.index)
            should.be_equal("assistant", msg.role)
            should.be_equal("tool_calls", msg.finish_reason)

            should.be_equal(2, #msg.tool_calls)
            -- * tool1:
            -- {"id":"call_809l7n8f","index":0,"type":"function", "function":{
            --    "name":"run_command",
            --    "arguments":"{\"command\":\"ls -la\"}"}}]},"finish_reason":null}
            first_call = msg.tool_calls[1]
            should.be_equal("call_809l7n8f", first_call.id)
            should.be_equal(0, first_call.index)
            should.be_equal("function", first_call.type)
            func = first_call["function"]
            should.be_equal("run_command", func.name)
            should.be_equal("{\"command\":\"ls -la\"}", func.arguments)
            -- * tool2:
            -- {"id":"call_oqp1e2a1","index":1,"type":"function", "function":{
            --    "name":"run_command",
            --    "arguments":"{\"command\":\"ls -la\",\"cwd\":\"/path/to/directory\"}"}}]},"finish_reason":null}
            second_call = msg.tool_calls[2]
            should.be_equal("call_oqp1e2a1", second_call.id)
            should.be_equal(1, second_call.index)
            should.be_equal("function", second_call.type)
            func = second_call["function"]
            should.be_equal("run_command", func.name)
            should.be_equal("{\"command\":\"ls -la\",\"cwd\":\"/path/to/directory\"}", func.arguments)
        end)
        -- TODO add a test that validates lookup on index/role per message... need a multi message scenario (if that's ever a thing... and not multi choice... literally need two messages at same time, streaming)

        it("streaming tool_calls (multiple SSE/deltas per tool_call) - vllm capture", function()
            -- local sses  = [[
            -- data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}
            -- data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"id":"chatcmpl-tool-ca99dda515524c6abe47d1ea22813507","type":"function","index":0,"function":{"name":"run_command"}}]},"logprobs":null,"finish_reason":null}]}
            -- data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"command\": \""}}]},"logprobs":null,"finish_reason":null}]}
            -- data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"ls"}}]},"logprobs":null,"finish_reason":null}]}
            -- data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]},"logprobs":null,"finish_reason":null}]}
            -- data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"content":""},"logprobs":null,"finish_reason":"tool_calls","stop_reason":null}]}
            -- data: [DONE]
            -- ]]
            local choices = [[
                {"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}
                {"index":0,"delta":{"tool_calls":[{"id":"chatcmpl-tool-ca99dda515524c6abe47d1ea22813507","type":"function","index":0,"function":{"name":"run_command"}}]},"logprobs":null,"finish_reason":null}
                {"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"command\": \""}}]},"logprobs":null,"finish_reason":null}
                {"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"ls"}}]},"logprobs":null,"finish_reason":null}
                {"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]},"logprobs":null,"finish_reason":null}
                {"index":0,"delta":{"content":""},"logprobs":null,"finish_reason":"tool_calls","stop_reason":null}
            ]]
            local request, frontend = call_on_delta(choices)
            should.be_equal(1, #request.messages)
            msg = request.messages[1]
            should.be_equal("assistant", msg.role)
            -- FYI VLLM IS NOT DUPLICATING ATTRS like role across all deltas, just on first one it seems
            should.be_equal(0, msg.index)
            should.be_equal("", msg.content)
            -- FYI I do not care about logprobs
            should.be_equal("tool_calls", msg.finish_reason)
            -- FYI stop_reason for now

            -- * tool delta 1:
            -- [{"id":"chatcmpl-tool-ca99dda515524c6abe47d1ea22813507","type":"function","index":0,"function":{"name":"run_command"}}
            should.be_equal(1, #msg.tool_calls)
            call = msg.tool_calls[1]
            should.be_equal("chatcmpl-tool-ca99dda515524c6abe47d1ea22813507", call.id)
            should.be_equal(0, call.index)
            should.be_equal("function", call.type)
            -- -- * function.name
            func = call["function"]
            should.be_equal("run_command", func.name)
            --
            -- * tool delta 2-4:
            -- [{"index":0,"function":{"arguments":"{\"command\": \""}}
            -- [{"index":0,"function":{"arguments":"ls"}}
            -- [{"index":0,"function":{"arguments":"\"}"}}
            --
            -- concatenate args:
            should.be_equal("{\"command\": \"ls\"}", func.arguments)
        end)

        -- TODO add vllm dual tool use test so I can validate that index is whats different

        it("llama-server tool calls - --jinja + qwen3coder30b (non- reasoning)", function()
            -- FYI see llama-server-tool-call.md for full response capture
            local choices = [[
                {"finish_reason":null,"index":0,"delta":{"role":"assistant","content":null}}
                {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"id":"CALL_ID","type":"function","function":{"name":"run_command","arguments":""}}]}}
                {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\""}}]}}
                {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"command"}}]}}
                {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\":"}}]}}
                {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\""}}]}}
                {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"pwd"}}]}}
                {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]}}
                {"finish_reason":"tool_calls","index":0,"delta":{}}
            ]]

            local request, frontend = call_on_delta(choices)
            should.be_equal(1, #request.messages)

            local msg = request.messages[1]
            should.be_equal(0, msg.index) -- do I care about this?
            should.be_equal(nil, msg.content) -- do I care about this?
            should.be_equal("assistant", msg.role)
            should.be_equal("tool_calls", msg.finish_reason)

            -- * validate accumulated tool call
            should.be_equal(1, #msg.tool_calls)
            call = msg.tool_calls[1]
            should.be_equal("CALL_ID", call.id)
            should.be_equal(0, call.index)
            should.be_equal("function", call.type)
            func = call["function"]
            should.be_equal("run_command", func.name)
            should.be_equal('{"command":"pwd"}', func.arguments)
        end)

        it("llama-server tool calls - TODO gptoss models + harmony?", function()
        end)

        it("llama-server qwen3coder30b leaking <tool_call>\n<function name=... - from mixed content + tool_call in one response", function()
            -- join content together
            --  cat lua/ask-openai/tools/tests/captures/weather-mixed-content-toolcall-sses.json | jq ".choices[0].delta.content" -r | grep -v null | string join ""

            -- FYI see llama-server-tool-call.md for full response capture
            local sses_json = vim.fn.readfile("lua/ask-openai/tools/tests/captures/weather-mixed-content-toolcall-sses.json")
            -- vim.print(ss_events)
            local frontend = FakeFrontend:new()
            local request = {}

            local sses = vim.iter(sses_json)
                :map(function(line)
                    return vim.json.decode(line, {})
                end)
                :map(function(sse)
                    return sse.choices
                end)
                :each(function(sse)
                    -- vim.print(sse[1])
                    curls.on_delta_update_message_history(sse[1], request)
                end)

            should.be_equal(1, #request.messages)

            local msg = request.messages[1]
            should.be_equal(0, msg.index)
            -- TODO this is current behavior... next I want to change the behavior to strip the <tool_call>... and after part
            should.be_equal("Hi there! Let me check the current weather for Washington DC for you.\n<tool_call>\n<function=get_current_weather", msg.content)
            should.be_equal("assistant", msg.role)
            should.be_equal("tool_calls", msg.finish_reason)
            --
            -- -- * validate accumulated tool call
            should.be_equal(1, #msg.tool_calls)
            call = msg.tool_calls[1]
            should.be_equal("CALL_ID", call.id)
            should.be_equal(0, call.index)
            should.be_equal("function", call.type)
            func = call["function"]
            should.be_equal("get_current_weather", func.name)
            -- cat lua/ask-openai/tools/tests/captures/weather-mixed-content-toolcall-sses.json | jq ".choices[0].delta.tool_calls[0].function.arguments" -r | grep -v null | string join ""
            should.be_equal('{"location":"Washington DC"}', func.arguments)
        end)
    end)
end)
