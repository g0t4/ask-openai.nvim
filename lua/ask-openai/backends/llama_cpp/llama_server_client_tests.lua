require('ask-openai.helpers.test_setup').modify_package_path()
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")
local should = require("devtools.tests.should")
local _describe = require("devtools.tests._describe")
local str = require("devtools.tests.str")
local json_client = require("ask-openai.backends.json_client")
local LlamaServerClient = require("ask-openai.backends.llama_cpp.llama_server_client")
local files = require("ask-openai.helpers.files")
local harmony = require("ask-openai.backends.models.gptoss.tokenizer").harmony

_describe("testing prompt rendering in llama-server with gpt-oss jinja template", function()
    local base_url = "http://build21.lan:8013"

    it("check model is gpt-oss", function()
        -- * action
        local response = LlamaServerClient.get_models(base_url)

        -- * assertions:
        assert.is_true(response.code == 200 or response.code == 201, "Expected successful HTTP status")
        local body = response.body
        assert.is_table(body.data, "Response does not contain a `data` array")
        assert.is_true(#body.data > 0, "No models were returned by the backend")
        -- vim.print(body.data)

        local model = body.data[1]
        local plain_text = true
        assert.matches("ggml-org_gpt-oss-", model.id, nil, plain_text)
        assert.same("llamacpp", model.owned_by, "MUST TEST WITH llama-server")
    end)

    local function print_prompt(prompt)
        assert.is_string(prompt, "prompt should be a string")
        print("\n" .. string.rep("-", 80))
        print(prompt)
        print(string.rep("-", 80) .. "\n")
    end

    local function split_messages(prompt)
        local messages = vim.split(prompt, harmony.START)
        -- PRN get rid of first empty? maybe after asserting it exists?
        return vim.iter(messages):map(function(m) return str(m) end):totable()
    end

    it("sends a single user message to the llama-server backend", function()
        -- * action
        local response = LlamaServerClient.apply_template(base_url, {
            messages = {
                TxChatMessage:user("Hello, can you rewrite this code?")
            }
        })

        -- * assertions:
        local prompt = response.body.prompt
        -- print_prompt(prompt)

        str(prompt):should_start_with(harmony.START)

        local messages = split_messages(prompt)

        local first = messages[1]
        expect(first == str("")) -- b/c started with harmony.START
        local system = messages[2]

        -- TODO str() needs to map string methods to the string! use it's instance_mt and selectively forward based on name?

        -- * bad way to compare strings (especially long strings, no diff):
        expect(system.str:find("Reasoning:"))
        -- expect(system.str:find("Rasoning:")) -- shows code line + values on failure (with some attempt to diff...).. falls apart on really long string compares
        -- * good way to compare strings b/c good diff on a failure!
        str(system):should_contain("Reasoning: medium")
        -- system:should_contain("Reasoning: low") -- try this to see nice diff on failure!

        -- PRN parse and extract template
    end)

    local function read_json_file(filename)
        local text = files.read_file_string(filename)
        if not text then
            return nil
        end
        return vim.json.decode(text)
    end

    local function split_messages_keep_start(prompt)
        --- split response so that it divides each message when it sees a harmony.START token
        ---     FYI I think I like this better in comments: harmony.START for the special token! TODO I can setup qwen.FIM_PREFIX etc! and use it in comments! for back to back tokens => try wrap in parens? (harmony.END)(harmony.START) key will be to have same name as I would use if using that same token in code via its constant... i.e. harmony.START!
        ---  DOES NOT return str() instances (easier to compare raw strings... only use str() for find etc)
        ---  SKIPS fake first message when harmony.START is right at the start
        local messages = vim.split(prompt, harmony.START)
        if messages[1] == "" then
            -- this happens when the first message appropirately starts at the start of the prompt
            table.remove(messages, 1)
        end
        return vim.iter(messages):map(function(m) return harmony.START .. m end):totable()
    end

    it("builtin_tools => python v1_chat_completions", function()
        do return end -- comment out to run

        local body = read_json_file("lua/ask-openai/backends/llama_cpp/jinja/tests/builtin/ask_run_python.json")
        body.chat_template_kwargs = {
            reasoning_effort = "low",
            builtin_tools = { "python" },
        }

        -- * action
        local response = LlamaServerClient.v1_chat_completions(base_url, body)

        -- * assertions:
        vim.print("\n\n****************************** prompt ***********************************", response.body.__verbose.prompt)
        vim.print("\n\n****************************** responsee (content) ***********************************", response.body.__verbose.content)
        -- * rendered _SYSTEM MESSAGE_ (not developer message) has 2 blurbs about the python tool but no tool definition in developer message (like you get with apply_patch in tools list) ... builtin tools are treated different
        -- # Tools
        --
        -- ## python
        --
        -- Use this tool to execute Python code in your chain of thought. The code will not be shown to the user. This tool should be used for internal reasoning, but not for code that is intended to be visible to the user (e.g. when creating plots, tables, or files).
        --
        -- When you send a message containing Python code to python, it will be executed in a stateful Jupyter notebook environment. python will respond with the output of the execution or time out after 120.0 seconds. The drive at '/mnt/data' can be used to save and persist user files. Internet access for this session is UNKNOWN. Depends on the cluster.


        -- * response - note no (harmony.CONSTRAIN) but "code" format is set:
        --  FYI new convention uses (harmony.SPECIAL) in comments! I like it better than {START} - ? convert {UPPERCASE} to this?
        -- (harmony.CHANNEL)analysis(harmony.MESSAGE) We need to test python tool. We'll run a simple command.(harmony.END)(harmony.START)assistant(harmony.CHANNEL)commentary to=python code(harmony.MESSAGE)print("Hello from python")
    end)

    -- FYI check jinja differnces:
    --   :e unsloth.jinja
    --   :vert diffsplit lua/ask-openai/backends/llama_cpp/jinja/ask-fixes.jinja

    it("apply_patch - with single, string argument only (not dict) - v1_chat_completions", function()
        do return end -- comment out to run

        local body = read_json_file("lua/ask-openai/backends/llama_cpp/jinja/tests/apply_patch/definition.json")
        body.chat_template_kwargs = {
            reasoning_effort = "low"
        }

        -- * action
        local response = LlamaServerClient.v1_chat_completions(base_url, body)

        -- * assertions:
        vim.print("\n\n****************************** prompt ***********************************", response.body.__verbose.prompt)
        vim.print("\n\n****************************** responsee (content) ***********************************", response.body.__verbose.content)
        -- vim.print(response)
        -- FYI my bad, it is a JSON string and not double encoded, I was looking at JSON response and forgot I needed to decode it once to get rid of llama-server's wrapper basically
        --   once I did that it was just "foo the bar" and had some " inside that were escaped:
        --    (harmony.CHANNEL)analysis(harmony.MESSAGE)We need to edit hello.lua. Use apply_patch.(harmony.END)(harmony.START)assistant(harmony.CHANNEL)commentary to=functions.apply_patch (harmony.CONSTRAIN)json(harmony.MESSAGE)"*** Begin Patch\n*** Update File: hello.lua\n@@\n-print(\"Hello\")\n+print(\"Hello Wor
    end)


    it("apply_patch - with single, dict w/ patch property - v1_chat_completions", function()
        do return end -- comment out to run

        local body = read_json_file("lua/ask-openai/backends/llama_cpp/jinja/tests/apply_patch/definition-dict.json")
        body.chat_template_kwargs = {
            reasoning_effort = "low"
        }

        -- * action
        local response = LlamaServerClient.v1_chat_completions(base_url, body)

        -- * assertions:
        vim.print(response)

        vim.print(response.body.__verbose.content)
        -- FYI here is sample model output (it isn't double encoded) and it is a JSON object now:
        --  and duh wes, it doesn't really matter either way b/c if its a JSON object it needs the exact same escaping of "... will look the same
        --   my thinking I need string was like... raw string (not JSON at all)... but the model doesn't seem to want to do that
        --   though, maybe I can coerce it to!
        --   TODO I need to test with full apply_patch.md dev message mods to see how models respond
        --
        -- (harmony.CHANNEL)analysis(harmony.MESSAGE)We need to modify hello.lua. Use apply_patch.(harmony.END)(harmony.START)assistant(harmony.CHANNEL)commentary to=functions.apply_patch (harmony.CONSTRAIN)json(harmony.MESSAGE){
        --   "patch": "*** Begin Patch\n*** Update File: hello.lua\n@@\n-print(\"Hello\")\n+print(\"Hello World\")\n*** End Patch"
        -- }
    end)

    it("apply_patch - with single, string argument only (not dict)", function()
        local expected_dev_apply_patch_with_string_arg = [[
]] .. harmony.msg_developer [[# Instructions

Your name is Qwenny
You can respond with markdown

# Tools

## functions

namespace functions {

// Patch a file
type apply_patch = (_: string) => any;

} // namespace functions]]

        local body = read_json_file("lua/ask-openai/backends/llama_cpp/jinja/tests/apply_patch/definition.json")

        -- * action
        local response = LlamaServerClient.apply_template(base_url, body)

        -- * assertions:
        local prompt = response.body.prompt
        -- print_prompt(prompt)

        -- str(prompt):should_contain(expected_tool_definition)
        local messages = split_messages_keep_start(prompt)
        local dev = messages[2]
        -- vim.print(dev)
        str(dev):should_contain(expected_dev_apply_patch_with_string_arg)

        -- 2. FYI! also see notes in lua/ask-openai/tools/inproc/apply_patch.lua
        -- 3. TODO? content type
        --    FYI MODEL responds with (harmony.CONSTRAIN)json in both cases dict/string... former is as double encoded dict (yikes) and later is as double encoded standalone string
        --    TODO can I just set it empty (include field .content_type set to "")
        --
        -- 4. TODO then when returning prior tool call, make sure content_type is set appropriately and that the template maps it correctly
        --    - this is the return trip for (harmony.CONSTRAIN)string (or w/e the model uses)
    end)
    it("apply_patch - with single patch property in a dictionary", function()
        local expected_dev_apply_patch_with_dict_arg = harmony.msg_developer [[# Instructions

Your name is Qwenny
You can respond with markdown

# Tools

## functions

namespace functions {

// Apply a patch
type apply_patch = (_: {
// file changes in custom diff format
patch: string,
}) => any;

} // namespace functions]]
        local body = read_json_file("lua/ask-openai/backends/llama_cpp/jinja/tests/apply_patch/definition-dict.json")

        -- * action
        local response = LlamaServerClient.apply_template(base_url, body)

        -- * assertions:
        local prompt = response.body.prompt
        -- print_prompt(prompt)

        local messages = split_messages_keep_start(prompt)
        local dev = messages[2]
        -- vim.print(dev)
        str(dev):should_contain(expected_dev_apply_patch_with_dict_arg)
    end)

    it("tool call request and result both avoid double encoding JSON arguments", function()
        local body = read_json_file("lua/ask-openai/backends/llama_cpp/jinja/tests/full_date_run_command.json")

        -- * action
        local response = LlamaServerClient.apply_template(base_url, body)

        -- * assertions:
        local prompt = response.body.prompt
        -- print_prompt(prompt)

        -- Full file is available should you want to diff but it won't work reliably b/c:
        --   1. tool args order is non-deterministic... randomly rearranges on every request!
        --   2. date in system message changes
        -- MOSTLY I saved the file so you can visualize the big picture w/o re-runing the request
        --
        -- local actual_prompt = files.read_file_string("lua/ask-openai/backends/llama_cpp/jinja/tests/full_date_run_command_prompt.harmony")
        -- should.be_same_colorful_diff(actual_prompt, prompt) -- FYI don't directly compare

        str(prompt):should_start_with(harmony.START)
        local expected_thinking = harmony.msg_assistant_analysis "We need to run date command."
        local expected_tool_call = harmony.start_assistant_json_tool_call("functions.run_command") .. harmony.message_call('{"command":"date"}')
        -- CONFIRMED per spec, assistant tool call _REQUESTS_, recipient `to=` comes _AFTER_ (harmony.CHANNEL)commentary
        --    but, it can also come before (in role) ...
        --    in testing:
        --      model generates AFTER  (see test below)
        --      harmony python+rust library generates BEFORE (see manual/harmony_library.py)
        --    so,
        --      I setup the ask-fixes.jinja to generate AFTER (so it matches model's gen)
        --      and my tree-sitter grammar handles both

        local expected_tool_result = harmony.START .. 'functions.run_command to=assistant' .. harmony.CHANNEL .. 'commentary'
            .. harmony.message_end '{"content":[{"text":"Sun Nov 30 19:35:10 CST 2025\\n","type":"text","name":"STDOUT"}]}'
        -- CONFIRMED per spec, for tool results, recipient `to=` comes _BEFORE_ (harmony.CHANNEL)commentary
        --   IIRC spec doesn't mention recipient in the channel (after channel/commentary) for tool result messages

        local messages = split_messages_keep_start(prompt)

        -- add back start token split point
        local actual_system = messages[2]
        local actual_thinking = messages[4]
        local actual_tool_call_request = messages[5]
        local actual_tool_result = messages[6]
        -- * chat message history is NOT 1-to-1 w/ harmony messages
        --   For example, this example's request.body.messages has 4 "input"/"chat" messages
        --   1. input message 1 - is role=system (could be role=developer too)
        --     BUT, the template renders two harmony messages: system and developer
        --     - what you pass in as role=system/developer (first message only) => maps to the harmony developer message
        --     - harmony system message is minimally configurable... basically has just date and reasoning level
        --   2. input message 2 is role=user => maps to harmony user role (1 to 1)
        --   3. input message 3 maps has both message.tool_calls and message.reasoning_content
        --      thus results in two harmony messages:
        --      1. role=assistant channel=analysis (thinking)
        --      2. role=assistant channel=commentary to=functions.run_command (tool call request)
        --   4. input message 4 is role=tool (tool call result, back to model)
        --      maps to 1 harmony message (1 to 1 basically)
        --      => role=functions.run_command to=assistant(recipient) channel=commentary
        --  TLDR 4 input messages => result in 6 harmony messages (7 if you count the prefill at the end to prompt final assistant response)

        should.be_same_colorful_diff(actual_thinking, expected_thinking)
        should.be_same_colorful_diff(actual_tool_call_request, expected_tool_call)
        should.be_same_colorful_diff(actual_tool_result, expected_tool_result)
    end)

    it("model formats tool call request with recipient AFTER " .. harmony.CHANNEL .. "commentary to=functions.xyz (not before/in the role)", function()
        local body = read_json_file("lua/ask-openai/backends/llama_cpp/jinja/tests/request_tool_call.json")

        local response = LlamaServerClient.v1_chat_completions(base_url, body)
        -- vim.print(response)

        -- FYI must be running w/ --verbose-prompt else won't get __verbose
        expect(response.body ~= nil)
        expect(response.body.__verbose ~= nil)
        expect(response.body.__verbose.content ~= nil)

        -- FYI PER SPEC, recipient can be in role or in channel
        --   => it is possible the model could generate it before, so far I have not seen it with this particular request
        --   and I do see different thinking (analysis) so it's not a seeding issue
        --   o
        --   if need be (operative words) => use different user message requests and/or different tool definitions and see if it changes placement

        local raw = response.body.__verbose.content
        -- vim.print(raw)
        -- FYI sample full response:
        -- (harmony.CHANNEL)analysis(harmony.MESSAGE)The user asks to check the time. We need to get current system time. Use run_command to execute date. Use appropriate command. On macOS (darwin) 'date' prints. We'll run.(harmony.END)(harmony.START)assistant(harmony.CHANNEL)commentary to=functions.run_command (harmony.CONSTRAIN)json(harmony.MESSAGE){
        -- "command": "date"
        -- }

        -- FYI I am not 100% sold on using builders in tests... we shall see... it's ok to rip these out!
        -- local likely = harmony.START .. [[assistant]] .. harmony.CHANNEL .. [[commentary to=functions.run_command ]] .. harmony.CONSTRAIN .. [[json]] .. harmony.MESSAGE
        local likely = harmony.start_assistant_json_tool_call("functions.run_command") .. harmony.MESSAGE
        str(raw):should_contain(likely)
    end)
end)
