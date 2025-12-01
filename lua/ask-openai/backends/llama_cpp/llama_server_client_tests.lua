require('ask-openai.helpers.test_setup').modify_package_path()
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")
local should = require("devtools.tests.should")
local str = require("devtools.tests.str")
local json_client = require("ask-openai.backends.json_client")
local LlamaServerClient = require("ask-openai.backends.llama_cpp.llama_server_client")
local files = require("ask-openai.helpers.files")

describe("testing prompt rendering in llama-server with gpt-oss jinja template", function()
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

    it("tool result renders w/o double encoded json", function()
        -- TODO tool call test the same thing
        -- TODO test formatting of tool definition in gptoss

        local body = read_json_file("models/llama_cpp/templates/gptoss/tests/full_date_run_command.json")

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
        -- local actual_prompt = files.read_file_string("models/llama_cpp/templates/gptoss/tests/full_date_run_command_prompt.harmony")
        -- should.be_same_colorful_diff(actual_prompt, prompt) -- FYI don't directly compare

        str(prompt):should_start_with("<|start|>")

        local expected_tool_call_request =
        [[<|start|>assistant to=functions.run_command<|channel|>commentary json<|message|>{"command":"date"}<|call|>]]

        local expected_tool_result =
        [[<|start|>functions.run_command to=assistant<|channel|>commentary<|message|>{"content":[{"text":"Sun Nov 30 19:35:10 CST 2025\n","type":"text","name":"STDOUT"}]}<|end|>]]

        --- split response so that it divides each message when it sees a <|start|> token
        ---  DOES NOT return str() instances (easier to compare raw strings... only use str() for find etc)
        ---  SKIPS fake first message when <|start|> is right at the start
        local function split_messages_keep_start(prompt)
            local messages = vim.split(prompt, "<|start|>")
            if messages[1] == "" then
                -- this happens when the first message appropirately starts at the start of the prompt
                table.remove(messages, 1)
            end
            return vim.iter(messages):map(function(m) return "<|start|>" .. m end):totable()
        end
        local messages = split_messages_keep_start(prompt)

        -- add back start token split point
        local actual_system = messages[2]
        local actual_tool_call_request = messages[5]
        local actual_tool_result = messages[6]

        should.be_same_colorful_diff(actual_tool_call_request, expected_tool_call_request)
        should.be_same_colorful_diff(actual_tool_result, expected_tool_result)
    end)
end)
