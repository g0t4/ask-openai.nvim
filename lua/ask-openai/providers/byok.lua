local function create_provider_for_func(get_bearer_token)
    local config = require("ask-openai.config")

    ---@return string
    local function get_chat_completions_url()
        -- TODO maybe rename this to get_default_chat_completions_url and let consumer of this handle the override?
        if config.get_options().api_url then
            return config.get_options().api_url
        end

        -- TODO enum of common APIs, DO NOT make into providers though
        -- default to OpenAI API if providing key
        return "https://api.openai.com/v1/chat/completions"
    end

    return {
        is_auto_configured = function()
            -- not participate in auto-configuration
            -- TODO use interface for this or get rid of "auto"
            return false
        end,
        get_chat_completions_url = get_chat_completions_url,
        get_bearer_token = get_bearer_token,
    }
end

return create_provider_for_func
