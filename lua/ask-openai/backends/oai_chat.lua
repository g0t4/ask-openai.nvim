local M = {}
local log = require("ask-openai.logs.logger").predictions()
local curl = require("ask-openai.backends.curl_streaming")

function M.curl_for(body, base_url, frontend)
    local url = base_url .. "/v1/chat/completions"
    return curl.reusable_curl_seam(body, url, frontend, M.parse_choice, M)
end

M.terminate = curl.terminate

function M.parse_choice(choice)
    -- ??? PUSH this entire class out into rewrites (only spot used)
    --  above is just a URL contant  (and body is chat/completions specific too so this is all DUMB, nothing is swappable)
    --  two primary points of difference:
    --    body/url of request
    --    SSE parser to get content / done / done_reason / reasoning/thinking ...

    -- TODO reasoning if already extracted?
    -- choice.delta.reasoning?/thinking? ollama splits this out, IIUC LM Studio does too... won't work if using harmony format with gpt-oss and its not parsed

    if choice.delta == nil or choice.delta.content == nil or choice.delta.content == vim.NIL then
        log:warn("WARN - unexpected, no delta in completion choice, what gives?!")
        return ""
    end
    return choice.delta.content
end

return M
