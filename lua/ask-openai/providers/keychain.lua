local M = {}

M.get_api_key_from_keychain = function()
    local handle = io.popen('security find-generic-password -s openai -a ask -w')
    if handle then
        local api_key = handle:read("*a"):gsub("%s+", "") -- remove any extra whitespace
        handle:close()
        return api_key
    else
        print("Failed to retrieve API key from Keychain.")
        return nil
    end
end

return M
