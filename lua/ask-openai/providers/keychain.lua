--- @module ask-openai.providers.keychain
--- @type Provider
local M = {}

M.get_api_key_from_keychain = function()
    local handle = io.popen('security find-generic-password -s openai -a ask -w')
    if handle then
        local api_key = handle:read("*a"):gsub("%s+", "") -- remove any extra whitespace
        handle:close()
        return api_key
    else
        -- TODO try error here?
        print("Failed to retrieve API key from Keychain.")
        return nil
    end
end

M.get_chat_completions_url = function()
    return "https://api.openai.com/v1/chat/completions"
end

M.get_bearer_token = function()
    return M.get_api_key_from_keychain()
end

return M
