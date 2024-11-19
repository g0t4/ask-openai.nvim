local config = require("ask-openai.config")

---@return string
local function get_bearer_token()
    -- TODO address keyless s/b empty but I check not empty in consumer
    return "foo" -- doesn't matter, i.e. ollama, LMStudio, etc
end

---@return string
local function get_chat_completions_url()
    if config.get_options().api_url then
        return config.get_options().api_url
    end

    -- https://github.com/ollama/ollama/blob/main/docs/api.md
    return "http://localhost:11434/api/chat"
end

return {
    get_chat_completions_url = get_chat_completions_url,
    get_bearer_token = get_bearer_token,
}
