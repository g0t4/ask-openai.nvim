local curl = require("ask-openai.backends.curl_streaming")
local log = require("ask-openai.logs.logger").predictions()

local M = {}
function M.curl_for(body, base_url, frontend)
    local url = base_url .. "/v1/completions"

    if body.tools ~= nil then
        error("tool use was requested, but this backend " .. url .. " does not support tools")
        return
    end

    local function parse_choice(choice)
        if choice.text == nil then
            log:warn("WARN - unexpected, no choice in completion, do you need to add special logic to handle this?")
            return ""
        end
        return choice.text
    end

    return curl.reusable_curl_seam(body, url, frontend, parse_choice, M)
end

M.terminate = curl.terminate



return M
