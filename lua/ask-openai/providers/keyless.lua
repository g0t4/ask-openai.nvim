local config = require("ask-openai.config")

---@return string
local function get_bearer_token()
    return "foo" -- doesn't matter, i.e. ollama, LMStudio, etc
end

---@return string
local function get_chat_completions_url()
    if config.get_options().api_url then
        return config.get_options().api_url
    end

    -- https://github.com/ollama/ollama/blob/main/docs/api.md
    -- TODO test this
    return "localhost:11434/api/chat"
end



return {
    is_auto_configured = function()
        -- not participate in auto-configuration
        return false
    end,
    get_chat_completions_url = get_chat_completions_url,
    get_bearer_token = get_bearer_token,
}
