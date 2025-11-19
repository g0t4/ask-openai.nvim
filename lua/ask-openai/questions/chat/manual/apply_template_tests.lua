require('ask-openai.helpers.test_setup').modify_package_path()
local ChatThread = require("ask-openai.questions.chat.thread")
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")
local model_params = require("ask-openai.questions.models.params")
local http = require("socket.http") -- luarocks install --lua-version=5.1  luasocket
local ltn12 = require("ltn12")

describe("testing prompt rendering in llama-server with gpt-oss jinja template", function()
    it("check model is gpt-oss", function()
        local response_body = {}

        -- TODO make helper that takes args table and returns body only (does basic assertions like 200 OK)
        local ok, status_code, response_headers, status_line = http.request {
            url     = "http://build21.lan:8013" .. "/v1/models",
            method  = "GET",
            headers = { ["Content-Type"] = "application/json", },
            sink    = ltn12.sink.table(response_body),
        }
        local response = nil
        if ok then
            local body_str = table.concat(response_body)
            response, _, err = vim.json.decode(body_str)
            if not response then
                error("Failed to decode JSON response: " .. tostring(err))
            end
        else
            error("HTTP request failed: " .. tostring(status_code))
        end

        assert.is_table(response, "Expected response table, got: " .. type(response))
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
            model = "", -- irrelevant for llama‑server
        })

        body_overrides.tools = nil

        local thread = ChatThread:new(messages, body_overrides, "http://build21.lan:8013")

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

        assert.is_number(result.code)
        assert.is_true(result.code == 200 or result.code == 201, "Expected successful HTTP status")
        assert.is_string(result.body)
        -- print(result.body)
        -- print()

        local parsed = vim.json.decode(result.body)
        assert.is_table(parsed, "Response body is not valid JSON")
        assert.is_string(parsed.prompt, "Expected `template` field in response")
        print(parsed.prompt)

        -- PRN parse and extract template
    end)
end)
