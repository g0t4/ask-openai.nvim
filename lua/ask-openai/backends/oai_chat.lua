local M = {}
local log = require("ask-openai.logs.logger").predictions()
local curl = require("ask-openai.backends.curl_streaming")

function M.curl_for(body, base_url, frontend)
    local url = base_url .. "/v1/chat/completions"

    local function parse_choice(choice)
        -- NOW I have access to request (url, body.model, etc) to be able to dynamically swap in the right SSE parser!
        --   I could even add another function that would handle aggregating and transforming the raw response (i.e. for harmony) into aggregate views (i.e. of thinking and final responses), also trigger events that way

        -- TODO return reasoning if already extracted?
        -- choice.delta.reasoning?/thinking? ollama splits this out, IIUC LM Studio does too... won't work if using harmony format with gpt-oss and its not parsed

        if choice == nil
            or choice.delta == nil
            or choice.delta.content == nil
            or choice.delta.content == vim.NIL
        then
            return ""
        end
        return choice.delta.content
    end

    return curl.reusable_curl_seam(body, url, frontend, parse_choice, M)
end

M.terminate = curl.terminate

return M
