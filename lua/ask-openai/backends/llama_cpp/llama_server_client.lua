local json_client = require("ask-openai.backends.json_client")

local LlamaServerClient = {
    ENDPOINTS = {
        URL_V1_MODELS = "/v1/models",
        URL_V1_CHAT_COMPLETIONS = "/v1/chat/completions",
        URL_APPLY_TEMPLATE = "/apply-template",
    }
}

---@param base_url string
---@param body table
---@param opts? HttpTimeoutOptions @optional timeout configuration (nil = no timeout)
---@return JsonClientResponse?
function LlamaServerClient.v1_chat_completions(base_url, body, opts)
    local url = base_url .. LlamaServerClient.ENDPOINTS.URL_V1_CHAT_COMPLETIONS
    return json_client.get_response_body(url, json_client.Methods.POST, body, opts)
end

---@param base_url string
---@param body table
---@param opts? HttpTimeoutOptions @optional timeout configuration (nil = no timeout)
---@return JsonClientResponse?
function LlamaServerClient.apply_template(base_url, body, opts)
    local url = base_url .. LlamaServerClient.ENDPOINTS.URL_APPLY_TEMPLATE
    return json_client.get_response_body(url, json_client.Methods.POST, body, opts)
end

---@param base_url string
---@param opts? HttpTimeoutOptions @optional timeout configuration (nil = no timeout)
---@return JsonClientResponse?
function LlamaServerClient.get_models(base_url, opts)
    local url = base_url .. LlamaServerClient.ENDPOINTS.URL_V1_MODELS
    return json_client.get_response_body(url, json_client.Methods.GET, nil, opts)
end

return LlamaServerClient
