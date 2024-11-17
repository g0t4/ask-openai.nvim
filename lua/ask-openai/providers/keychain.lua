--- @return string|nil - nil if not set in keychain, else the keychain value
local config = require("ask-openai.config")

local function get_api_key_from_keychain()
    local service = config.user_opts.keychain.service
    local account = config.user_opts.keychain.account

    local handle = io.popen('security find-generic-password -s ' .. service .. ' -a ' .. account .. ' -w')
    if handle then
        local api_key = handle:read("*a"):gsub("%s+", "") -- remove any extra whitespace
        handle:close()
        if api_key ~= "" then
            return api_key
        end
    end
    return nil
end

local function get_chat_completions_url()
    return "https://api.openai.com/v1/chat/completions"
end

local function get_bearer_token()
    -- TODO cache after first run, how long does it take to read each time? honestly it seems faster than using gh copilot w/o caching
    local api_key = get_api_key_from_keychain()
    if api_key then
        return api_key
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
