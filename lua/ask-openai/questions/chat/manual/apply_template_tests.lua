require('ask-openai.helpers.test_setup').modify_package_path()
local ChatThread = require("ask-openai.questions.chat.thread")
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")
local model_params = require("ask-openai.questions.models.params")
local http = require("socket.http") -- luarocks install --lua-version=5.1  luasocket
local ltn12 = require("ltn12")

describe("testing prompt rendering in llama-server with gpt-oss jinja template", function()
    local base_url = "http://build21.lan:8013"
    local URL_V1_MODELS = base_url .. "/v1/models"
    local URL_V1_CHAT_COMPLETIONS = base_url .. "/v1/chat/completions"
    local URL_APPLY_TEMPLATE = base_url .. "/apply-template"

    local function get_json_response(url, method, body)
        local response_body = {}
        local source = nil
        if body then
            source = ltn12.source.string(body)
        end
        local res, code, headers, status = http.request {
            url = url,
            method = method,
            headers = {
                ["Content-Type"] = "application/json",
            },
            source = source,
            sink = ltn12.sink.table(response_body),
        }
        local result = {
            code = code,
            body = table.concat(response_body),
        }

        assert.is_number(result.code)
        assert.is_true(result.code == 200 or result.code == 201, "Expected successful HTTP status")
        assert.is_string(result.body)
        -- print(result.body)
        -- print()

        local parsed = vim.json.decode(result.body)
        return parsed
    end

    it("check model is gpt-oss", function()
        local response = get_json_response(URL_V1_MODELS, "GET")

        assert.is_table(response.data, "Response does not contain a `data` array")
        assert.is_true(#response.data > 0, "No models were returned by the backend")
        -- vim.print(response.data)

        local model = response.data[1]
        local plain_text = true

        -- verify gpt-oss on llama-server
        assert.matches("ggml-org_gpt-oss-", model.id, nil, plain_text)
        assert.same("llamacpp", model.owned_by, "MUST TEST WITH llama-server")
    end)

    it("sends a single user message to the llama-server backend", function()
        local user_msg = TxChatMessage:user("Hello, can you rewrite this code?")
        local messages = { user_msg }

        local body_overrides = model_params.new_gptoss_chat_body_llama_server({
            messages = messages,
        })

        local thread = ChatThread:new(body_overrides, base_url)

        local body = vim.json.encode(thread.params)
        local parsed = get_json_response(URL_APPLY_TEMPLATE, "POST", body)

        assert.is_table(parsed, "Response body is not valid JSON")
        assert.is_string(parsed.prompt, "Expected `template` field in response")
        print(parsed.prompt)

        -- PRN parse and extract template
    end)
end)
