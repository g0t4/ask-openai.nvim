--- @return string|nil - nil if not set in keychain, else the keychain value
local config = require("ask-openai.config")

local function get_api_key_from_keychain()
    local service = config.get_options().keychain.service
    local account = config.get_options().keychain.account

    local handle = io.popen('security find-generic-password -s ' .. service .. ' -a ' .. account .. ' -w')
    if handle then
        local api_key = handle:read("*a"):gsub("%s+", "") -- remove any extra whitespace
        handle:close()

        return api_key -- return empty is fine, is checked by consumer
    end
    return nil
end

local function get_chat_completions_url()
    if config.get_options().api_url then
        return config.get_options().api_url
    end

    return "https://api.openai.com/v1/chat/completions"
end

local api_key_cached = nil
local function get_bearer_token()
    if api_key_cached == nil then
        api_key_cached = get_api_key_from_keychain()
    end

    if api_key_cached then
        return api_key_cached
    else
        error("Failed to retrieve API key from Keychain.")
    end
end

local function is_auto_configured()
    return get_api_key_from_keychain() ~= nil
end

--- @type Provider
return {
    is_auto_configured = is_auto_configured,
    get_bearer_token = get_bearer_token,
    get_chat_completions_url = get_chat_completions_url,
}
