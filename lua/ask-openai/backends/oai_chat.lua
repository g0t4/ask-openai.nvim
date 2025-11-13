local log = require("ask-openai.logs.logger").predictions()
local curl = require("ask-openai.backends.curl_streaming")

---@class OaiChatMiddle : CurlMiddle
local M = {}

---@param body table
---@param base_url string
---@param frontend StreamingFrontend
---@return LastRequest?
function M.curl_for(body, base_url, frontend)
    local url = base_url .. "/v1/chat/completions"

    ---@type ExtractGeneratedTextFunction
    local function extract_generated_text(choice)
        -- NOW I have access to request (url, body.model, etc) to be able to dynamically swap in the right SSE parser!
        --   I could even add another function that would handle aggregating and transforming the raw response (i.e. for harmony) into aggregate views (i.e. of thinking and final responses), also trigger events that way
        if choice == nil
            or choice.delta == nil
            or choice.delta.content == nil
            or choice.delta.content == vim.NIL
        then
            return ""
        end
        return choice.delta.content
    end

    return curl.reusable_curl_seam(body, url, frontend, extract_generated_text, M)
end

M.terminate = curl.terminate

return M
