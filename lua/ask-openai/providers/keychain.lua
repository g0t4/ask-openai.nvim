--- @return string|nil - nil if not set in keychain, else the keychain value
local function get_api_key_from_keychain()
    -- TODO configurable keychain service/account name?
    local handle = io.popen('security find-generic-password -s openai -a ask -w')
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

-- M.get_bearer_token = function()
local function get_bearer_token()
    -- return get_api_key_from_keychain()
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
