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
                curls.on_delta_update_message_history(delta_table, frontend, request)
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

            -- PROPMT:
            -- [TRACE] body: {"messages":[{"content":"Your name is Qwenny...","role":"system"},{"content":"what is the current directory?:","role":"user"}],"temperature":0.3,"model":"qwen3coder30b","tools":[{"type":"function","function":{"name":"run_command","parameters":{"type":"object","properties":{"workdir":{"description":"Optional, current working directory","type":"string"},"command":{"description":"Command with args","type":"string"},"stdin":{"description":"Optional, text to pipe into the command's STDIN. For example, pass a python script to python3. Or, pass text for a new file to the cat command to create it!","type":"string"}},"required":["command"]},"description":"Run a command on this darwin machine"}}],"stream":true}

            -- {"choices":[{"finish_reason":null,"index":0,"delta":{"role":"assistant","content":null}}],"created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
            -- {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"id":"v2dhUNilw8En9qFqCAHEz5Ow0GnQsclc","type":"function","function":{"name":"run_command","arguments":""}}]}}],"created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
            -- {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\""}}]}}],"created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
            -- {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"command"}}]}}],"created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
            -- {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\":"}}]}}],"created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
            -- {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\""}}]}}],"created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
            -- {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"pwd"}}]}}],"created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
            -- {"choices":[{"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]}}],"created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
            -- {"choices":[{"finish_reason":"tool_calls","index":0,"delta":{}}],"created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk","timings":{"cache_n":0,"prompt_n":463,"prompt_ms":62.703,"prompt_per_token_ms":0.13542764578833694,"prompt_per_second":7384.016713713857,"predicted_n":20,"predicted_ms":102.018,"predicted_per_token_ms":5.1009,"predicted_per_second":196.04383540159577},"__verbose":{"index":0,"content":"","tokens":[],"id_slot":0,"stop":true,"model":"qwen3coder30b","tokens_predicted":20,"tokens_evaluated":463,"generation_settings":{"n_predict":-1,"seed":4294967295,"temperature":0.30000001192092896,"dynatemp_range":0.0,"dynatemp_exponent":1.0,"top_k":40,"top_p":0.949999988079071,"min_p":0.05000000074505806,"top_n_sigma":-1.0,"xtc_probability":0.0,"xtc_threshold":0.10000000149011612,"typical_p":1.0,"repeat_last_n":64,"repeat_penalty":1.0,"presence_penalty":0.0,"frequency_penalty":0.0,"dry_multiplier":0.0,"dry_base":1.75,"dry_allowed_length":2,"dry_penalty_last_n":65536,"dry_sequence_breakers":["\n",":","\"","*"],"mirostat":0,"mirostat_tau":5.0,"mirostat_eta":0.10000000149011612,"stop":[],"max_tokens":-1,"n_keep":0,"n_discard":0,"ignore_eos":false,"stream":true,"logit_bias":[],"n_probs":0,"min_keep":0,"grammar":"any-tool-call ::= ( run-command-call ) space\nchar ::= [^\"\\\\\\x7F\\x00-\\x1F] | [\\\\] ([\"\\\\bfnrt] | \"u\" [0-9a-fA-F]{4})\nroot ::= tool-call\nrun-command-args ::= \"{\" space run-command-args-command-kv ( \",\" space ( run-command-args-workdir-kv run-command-args-workdir-rest | run-command-args-stdin-kv ) )? \"}\" space\nrun-command-args-command-kv ::= \"\\\"command\\\"\" space \":\" space string\nrun-command-args-stdin-kv ::= \"\\\"stdin\\\"\" space \":\" space string\nrun-command-args-workdir-kv ::= \"\\\"workdir\\\"\" space \":\" space string\nrun-command-args-workdir-rest ::= ( \",\" space run-command-args-stdin-kv )?\nrun-command-call ::= \"{\" space run-command-call-name-kv \",\" space run-command-call-arguments-kv \"}\" space\nrun-command-call-arguments ::= \"{\" space run-command-call-arguments-command-kv ( \",\" space ( run-command-call-arguments-workdir-kv run-command-call-arguments-workdir-rest | run-command-call-arguments-stdin-kv ) )? \"}\" space\nrun-command-call-arguments-command-kv ::= \"\\\"command\\\"\" space \":\" space string\nrun-command-call-arguments-kv ::= \"\\\"arguments\\\"\" space \":\" space run-command-call-arguments\nrun-command-call-arguments-stdin-kv ::= \"\\\"stdin\\\"\" space \":\" space string\nrun-command-call-arguments-workdir-kv ::= \"\\\"workdir\\\"\" space \":\" space string\nrun-command-call-arguments-workdir-rest ::= ( \",\" space run-command-call-arguments-stdin-kv )?\nrun-command-call-name ::= \"\\\"run_command\\\"\" space\nrun-command-call-name-kv ::= \"\\\"name\\\"\" space \":\" space run-command-call-name\nrun-command-function-tag ::= \"<function\" ( \"=run_command\" | \" name=\\\"run_command\\\"\" ) \">\" space run-command-args \"</function>\" space\nspace ::= | \" \" | \"\\n\"{1,2} [ \\t]{0,20}\nstring ::= \"\\\"\" char* \"\\\"\" space\ntool-call ::= run-command-function-tag | wrappable-tool-call | ( \"```\\n\" | \"```json\\n\" | \"```xml\\n\" ) space wrappable-tool-call space \"```\" space \nwrappable-tool-call ::= ( any-tool-call | \"<tool_call>\" space any-tool-call \"</tool_call>\" | \"<function_call>\" space any-tool-call \"</function_call>\" | \"<response>\"  space any-tool-call \"</response>\" | \"<tools>\"     space any-tool-call \"</tools>\" | \"<json>\"      space any-tool-call \"</json>\" | \"<xml>\"      space any-tool-call \"</xml>\" | \"<JSON>\"      space any-tool-call \"</JSON>\" ) space\n","grammar_lazy":true,"grammar_triggers":[{"type":1,"value":"<function=run_command>"},{"type":2,"value":"<function\\s+name\\s*=\\s*\"run_command\""},{"type":3,"value":"(?:<think>[\\s\\S]*?</think>\\s*)?\\s*((?:<tool_call>|<function|(?:```(?:json|xml)?\n\\s*)?(?:<function_call>|<tools>|<xml><json>|<response>)?\\s*\\{\\s*\"name\"\\s*:\\s*\"(?:run_command)\"))[\\s\\S]*"}],"preserved_tokens":[73594,151657,151658,151667,151668],"chat_format":"Hermes 2 Pro","reasoning_format":"auto","reasoning_in_content":false,"thinking_forced_open":false,"samplers":["penalties","dry","top_n_sigma","top_k","typ_p","top_p","min_p","xtc","temperature"],"speculative.n_max":16,"speculative.n_min":0,"speculative.p_min":0.75,"timings_per_token":false,"post_sampling_probs":false,"lora":[]},"prompt":"<|im_start|>system\nYour name is Qwenny...\n\nYou have access to the following functions:\n\n<tools>\n<function>\n<name>run_command</name>\n<description>Run a command on this darwin machine</description>\n<parameters>\n<parameter>\n<name>workdir</name>\n<type>string</type>\n<description>Optional, current working directory</description>\n</parameter>\n<parameter>\n<name>command</name>\n<type>string</type>\n<description>Command with args</description>\n</parameter>\n<parameter>\n<name>stdin</name>\n<type>string</type>\n<description>Optional, text to pipe into the command's STDIN. For example, pass a python script to python3. Or, pass text for a new file to the cat command to create it!</description>\n</parameter>\n<required>['command']</required>\n</parameters>\n</function>\n</tools>\n\nIf you choose to call a function ONLY reply in the following format with NO suffix:\n\n<tool_call>\n<function=example_function_name>\n<parameter=example_parameter_1>\nvalue_1\n</parameter>\n<parameter=example_parameter_2>\nThis is the value for the second parameter\nthat can span\nmultiple lines\n</parameter>\n</function>\n</tool_call>\n\n<IMPORTANT>\nReminder:\n- Function calls MUST follow the specified format: an inner <function=...></function> block must be nested within <tool_call></tool_call> XML tags\n- Required parameters MUST be specified\n- You may provide optional reasoning for your function call in natural language BEFORE the function call, but NOT after\n- If there is no function call available, answer the question like normal with your current knowledge and do not tell the user about function calls\n</IMPORTANT><|im_end|>\n<|im_start|>user\nwhat is the current directory?:<|im_end|>\n<|im_start|>assistant\n","has_new_line":true,"truncated":false,"stop_type":"eos","stopping_word":"","tokens_cached":482,"timings":{"cache_n":0,"prompt_n":463,"prompt_ms":62.703,"prompt_per_token_ms":0.13542764578833694,"prompt_per_second":7384.016713713857,"predicted_n":20,"predicted_ms":102.018,"predicted_per_token_ms":5.1009,"predicted_per_second":196.04383540159577}}}

        end)

        it("llama-server tool calls - TODO gptoss models + harmony?", function()
        end)
    end)
end)
