require('ask-openai.helpers.test_setup').modify_package_path()
local ChatThread = require("ask-openai.questions.chat.thread")
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")
local model_params = require("ask-openai.questions.models.params")
local http = require("socket.http") -- luarocks install --lua-version=5.1  luasocket
local ltn12 = require("ltn12") -- also from luasocket
local should = require("devtools.tests.should")

describe("testing prompt rendering in llama-server with gpt-oss jinja template", function()
    local base_url = "http://build21.lan:8013"
    local URL_V1_MODELS = base_url .. "/v1/models"
    local URL_V1_CHAT_COMPLETIONS = base_url .. "/v1/chat/completions"
    local URL_APPLY_TEMPLATE = base_url .. "/apply-template"

    ---@enum METHODS
    local METHODS = {
        GET = "GET",
        POST = "POST",
    }

    ---@param method METHODS
    local function get_json_response(url, method, request_body)
        local response_body = {}
        local source = nil
        if request_body then
            request_body_json = vim.json.encode(request_body)
            source = ltn12.source.string(request_body_json)
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

        -- FYI if decode fails, will throw so no need to verify anything else in that case!
        return vim.json.decode(result.body)
    end

    it("check model is gpt-oss", function()
        local response = get_json_response(URL_V1_MODELS, METHODS.GET)

        assert.is_table(response.data, "Response does not contain a `data` array")
        assert.is_true(#response.data > 0, "No models were returned by the backend")
        -- vim.print(response.data)

        local model = response.data[1]
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

    it("sends a single user message to the llama-server backend", function()
        local response = get_json_response(URL_APPLY_TEMPLATE, METHODS.POST, {
            messages = {
                TxChatMessage:user("Hello, can you rewrite this code?")
            }
        })

        print_prompt(response.prompt)
        local prompt_lines = vim.split(response.prompt, "\n")

        -- should.be_same_colorful_diff({ "Reasoning:" }, prompt_lines) -- more helpful
        -- should.be_same_colorful_diff("Reasoning:", response.prompt)

        -- PRN parse and extract template
    end)
end)
