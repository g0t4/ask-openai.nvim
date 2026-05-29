local json_client = require("ask-openai.backends.json_client")

local LlamaServerClient = {
    ENDPOINTS = {
        URL_V1_MODELS = "/v1/models",
        URL_V1_CHAT_COMPLETIONS = "/v1/chat/completions",
        URL_APPLY_TEMPLATE = "/apply-template",
    }
}

---@param base_url string
---@param timeout_s? integer @curl --max-time in seconds (nil = no timeout)
---@return JsonClientResponse?
function LlamaServerClient.v1_chat_completions(base_url, body, timeout_s)
    local url = base_url .. LlamaServerClient.ENDPOINTS.URL_V1_CHAT_COMPLETIONS
    return json_client.get_response_body(url, json_client.Methods.POST, body, timeout_s)
end

---@param base_url string
---@param timeout_s? integer @curl --max-time in seconds (nil = no timeout)
---@return JsonClientResponse?
function LlamaServerClient.apply_template(base_url, body, timeout_s)
    local url = base_url .. LlamaServerClient.ENDPOINTS.URL_APPLY_TEMPLATE
    return json_client.get_response_body(url, json_client.Methods.POST, body, timeout_s)
end

---@param base_url string
---@param timeout_s? integer @curl --max-time in seconds (nil = no timeout)
---@return JsonClientResponse?
function LlamaServerClient.get_models(base_url, timeout_s)
    local url = base_url .. LlamaServerClient.ENDPOINTS.URL_V1_MODELS
    return json_client.get_response_body(url, json_client.Methods.GET, nil, timeout_s)
end

return LlamaServerClient
