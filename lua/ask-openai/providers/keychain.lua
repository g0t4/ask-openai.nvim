local function is_auto_configured()
    -- TODO discoverable function for auto provider
    return false
end

local function get_api_key_from_keychain()
    -- TODO configurable keychain service/account name?
    local handle = io.popen('security find-generic-password -s openai -a ask -w')
    if handle then
        local api_key = handle:read("*a"):gsub("%s+", "") -- remove any extra whitespace
        handle:close()
        return api_key
    else
        error("Failed to retrieve API key from Keychain.")
    end
end

local function get_chat_completions_url()
    return "https://api.openai.com/v1/chat/completions"
end

-- M.get_bearer_token = function()
local function get_bearer_token()
    return get_api_key_from_keychain()
end

--- @type Provider
return {
    get_bearer_token = get_bearer_token,
    get_chat_completions_url = get_chat_completions_url,
}
