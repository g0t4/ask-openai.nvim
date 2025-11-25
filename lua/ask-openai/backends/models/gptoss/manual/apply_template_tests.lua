require('ask-openai.helpers.test_setup').modify_package_path()
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")
local should = require("devtools.tests.should")
local str = require("devtools.tests.str")
local json_client = require("ask-openai.backends.json_client")
local LlamaServerClient = require("ask-openai.backends.llama_cpp.llama_server_client")

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

    -- # TODO try writing a simple eval/test case of asking for the date, given the fixed date in the prompt...
    --    user: What is the date?
    --    extract and verify value provided?
    -- #   TODO and maybe another test of the actual date using tools + run_command
    --    leave current date in prompt and as it to verify the date?
    --    remove date and just ask for date w/ tools available
end)
