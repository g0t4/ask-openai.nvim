local json_client = require("ask-openai.backends.json_client")

--
-- ModelInfo: strongly-typed representation of llama-server /v1/models model data
--

---@class ModelInfo
---@field name string @The model identifier (e.g. "ggml-org/Qwen3.6-35B-A3B-GGUF:Q8_0")
---@field alias string @The primary alias (first entry from aliases array, or empty string)
---@field created integer @Unix timestamp when the model was created/registered
---@field owned_by string @The entity that owns/created this model (e.g. "llamacpp")
---@field vocabulary_size integer @Number of tokens in the model's vocabulary
---@field context_length integer @Maximum context window size the model supports
---@field context_length_train integer @Context window size the model was trained on
---@field embedding_dimension integer @Dimensionality of the model's embedding space
---@field parameter_count integer @Total number of parameters in the model
---@field model_size_bytes integer @Size of the model file in bytes

local ModelInfo = {}
ModelInfo.__index = ModelInfo

---@param id string
---@param aliases string[]
---@param created integer
---@param owned_by string
---@param meta table @Raw meta table from the API response
---@return ModelInfo
function ModelInfo:new(id, aliases, created, owned_by, meta)
    local obj = {
        name = id,
        alias = #aliases > 0 and aliases[1] or "",
        created = created,
        owned_by = owned_by,
        vocabulary_size = meta.n_vocab or 0,
        context_length = meta.n_ctx or 0,
        context_length_train = meta.n_ctx_train or 0,
        embedding_dimension = meta.n_embd or 0,
        parameter_count = meta.n_params or 0,
        model_size_bytes = meta.size or 0,
    }
    setmetatable(obj, ModelInfo)
    return obj
end

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

---Extract a ModelInfo from a raw /v1/models API response body.
---
---Prefers the OpenAI-compatible `.data` array, falls back to the older `.models`
---array. Only ever looks at the first entry (index 1).
---
---@param body table @Decoded JSON response from the llama-server /v1/models endpoint
---@return ModelInfo?
function LlamaServerClient.extract_model_info(body)
    if type(body) ~= "table" then
        return nil
    end

    -- Primary: OpenAI-compatible response shape with .data array
    if type(body.data) == "table" and #body.data > 0 then
        local first_model = body.data[1]
        if type(first_model) ~= "table" then
            return nil
        end

        -- Need at least an id (and preferably meta)
        if not first_model.id then
            return nil
        end

        local aliases = type(first_model.aliases) == "table" and first_model.aliases or {}
        local meta = type(first_model.meta) == "table" and first_model.meta or {}

        return ModelInfo:new(
            first_model.id,
            aliases,
            first_model.created or 0,
            first_model.owned_by or "",
            meta
        )
    end

    -- Fallback: older shape with .models array (e.g. Ollama-style responses)
    if type(body.models) == "table" and #body.models > 0 then
        local first_model = body.models[1]
        if type(first_model) == "table" and first_model.name then
            return ModelInfo:new(
                first_model.name,
                {},
                0,
                "",
                {}
            )
        end
    end

    return nil
end

---Query the llama-server for the first model's full information.
---
---@param base_url string @The base URL of the llama-server (e.g. "http://paxy.lan:8012")
---@param opts? HttpTimeoutOptions @optional timeout configuration (nil = no timeout)
---@return ModelInfo? @Model info object, or nil on failure
function LlamaServerClient.get_model_info(base_url, opts)
    local response = LlamaServerClient.get_models(base_url, opts)
    if not response or response.code ~= 200 then
        return nil
    end
    return LlamaServerClient.extract_model_info(response.body)
end

return LlamaServerClient
