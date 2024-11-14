local M = {}

function M.get_openai_key()
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

-- TODO get copilot key and use it?

return M
