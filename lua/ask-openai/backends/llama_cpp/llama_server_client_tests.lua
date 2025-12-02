require('ask-openai.helpers.test_setup').modify_package_path()
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")
local should = require("devtools.tests.should")
local _describe = require("devtools.tests._describe")
local str = require("devtools.tests.str")
local json_client = require("ask-openai.backends.json_client")
local LlamaServerClient = require("ask-openai.backends.llama_cpp.llama_server_client")
local files = require("ask-openai.helpers.files")

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
        local messages = vim.split(prompt, "<|start|>")
        -- for i, message in ipairs(messages) do
        --     print(string.format("MESSAGE: <|start|>%q", message))
        -- end
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

        str(prompt):should_start_with("<|start|>")

        local messages = split_messages(prompt)

        local first = messages[1]
        expect(first == str("")) -- b/c started with <|start|>
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
        --- split response so that it divides each message when it sees a <|start|> token
        ---  DOES NOT return str() instances (easier to compare raw strings... only use str() for find etc)
        ---  SKIPS fake first message when <|start|> is right at the start
        local messages = vim.split(prompt, "<|start|>")
        if messages[1] == "" then
            -- this happens when the first message appropirately starts at the start of the prompt
            table.remove(messages, 1)
        end
        return vim.iter(messages):map(function(m) return "<|start|>" .. m end):totable()
    end

    -- FYI check jinja differnces:
    --   :e unsloth.jinja
    --   :vert diffsplit lua/ask-openai/backends/llama_cpp/jinja/ask-fixes.jinja

    it("apply_patch - with single, string argument only (not dict)", function()
        local expected_dev_apply_patch_with_string_arg = [[
<|start|>developer<|message|># Instructions

Your name is Qwenny
You can respond with markdown

# Tools

## functions

namespace functions {

// Patch a file
type apply_patch = (_: string) => any;

} // namespace functions<|end|>]]

        -- TODO how about (patch: string) => any;
        --   and/or how can I put the description of the arg on it?
        --   interesting harmony library drops description/name of arg if its type==string too!

        local body = read_json_file("lua/ask-openai/backends/llama_cpp/jinja/tests/apply_patch/definition.json")
        -- TODO add v1_chat_completions REAL TEST to see how model responds (probably need to add dev message with apply_patch.md to get a realistic response? maybe not?)

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

        -- 1. TODO! implement template change to support (_: string) for param
        --    FYI template treats this as () => any    ... NO ARGS!
        --    TODO s/b simple check if type==string and if so then just (string)... I started this somewhere already
        -- 2. FYI! also see notes in lua/ask-openai/tools/inproc/apply_patch.lua
        -- 3. TODO? content type
        --    TODO check what the model generates for constrain|> (if anything)...
        --    TODO can I just set it empty (include field .content_type set to "")
        --
        -- 4. TODO then when returning prior tool call, make sure content_type is set appropriately and that the template maps it correctly
        --    - this is the return trip for <|constrain|>string (or w/e the model uses)
    end)
    it("apply_patch - with single patch property in a dictionary", function()
        local expected_dev_apply_patch_with_dict_arg = [[
<|start|>developer<|message|># Instructions

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

} // namespace functions<|end|>]]


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

        str(prompt):should_start_with("<|start|>")
        local expected_thinking
        = [[<|start|>assistant<|channel|>analysis<|message|>We need to run date command.<|end|>]]

        local expected_tool_call_request
        = [[<|start|>assistant<|channel|>commentary to=functions.run_command <|constrain|>json<|message|>{"command":"date"}<|call|>]]
        -- CONFIRMED per spec, assistant tool call _REQUESTS_, recipient `to=` comes _AFTER_ <|channel|>commentary
        --    but, it can also come before (in role) ...
        --    in testing:
        --      model generates AFTER  (see test below)
        --      harmony python+rust library generates BEFORE (see manual/harmony_library.py)
        --    so,
        --      I setup the ask-fixes.jinja to generate AFTER (so it matches model's gen)
        --      and my tree-sitter grammar handles both

        local expected_tool_result
        = [[<|start|>functions.run_command to=assistant<|channel|>commentary<|message|>{"content":[{"text":"Sun Nov 30 19:35:10 CST 2025\n","type":"text","name":"STDOUT"}]}<|end|>]]
        -- CONFIRMED per spec, for tool results, recipient `to=` comes _BEFORE_ <|channel|>commentary
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
        should.be_same_colorful_diff(actual_tool_call_request, expected_tool_call_request)
        should.be_same_colorful_diff(actual_tool_result, expected_tool_result)
    end)

    it("model formats tool call request with recipient AFTER <|channel|>commentary to=functions.xyz (not before/in the role)", function()
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
        -- <|channel|>analysis<|message|>The user asks to check the time. We need to get current system time. Use run_command to execute date. Use appropriate command. On macOS (darwin) 'date' prints. We'll run.<|end|><|start|>assistant<|channel|>commentary to=functions.run_command <|constrain|>json<|message|>{
        -- "command": "date"
        -- }

        local likely = [[<|start|>assistant<|channel|>commentary to=functions.run_command <|constrain|>json<|message|>]]
        str(raw):should_contain(likely)
    end)
end)
