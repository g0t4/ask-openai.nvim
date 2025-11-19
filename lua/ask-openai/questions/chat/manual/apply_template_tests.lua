-- TODO standardize on one of the test setup approaches (both have devtools):
-- require('ask-openai.helpers.testing') -- devtools only, looks older, I probably forgot about this and then made the second one:
require('ask-openai.helpers.test_setup').modify_package_path()

local ChatThread = require("ask-openai.questions.chat.thread")
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")
local model_params = require("ask-openai.questions.models.params")

local http = require("socket.http") -- simple http client for test
-- luarocks install --lua-version=5.1  luasocket

describe("apply_template with a simple thread", function()
    it("sends a single user message to the llama-server backend", function()
        -- Build a single‑user message
        local user_msg = TxChatMessage:user("Hello, can you rewrite this code?")
        local messages = { user_msg }

        -- Minimal ChatParams for llama‑server
        local body_overrides = model_params.new_gptoss_chat_body_llama_server({
            messages = messages,
            model = "", -- irrelevant for llama‑server
        })

        -- No tools for this simple test
        body_overrides.tools = nil

        -- Create the thread
        local thread = ChatThread:new(messages, body_overrides, "http://build21.lan:8013")

        -- Simulate the apply_template call (the real function sends the HTTP request)
        local function apply_template(thread)
            local url = thread.base_url .. "/apply-template"
            local body = vim.json.encode(thread.params)
            local response_body = {}
            local res, code, headers, status = http.request {
                url = url,
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Length"] = #body,
                },
                source = ltn12.source.string(body),
                sink = ltn12.sink.table(response_body),
            }
            return {
                code = code,
                body = table.concat(response_body),
            }
        end

        local result = apply_template(thread)

        -- Basic assertions
        assert.is_number(result.code)
        assert.is_true(result.code == 200 or result.code == 201, "Expected successful HTTP status")
        assert.is_string(result.body)
        print(result.body)
    end)
end)
