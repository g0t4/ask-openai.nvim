local curl = require("ask-openai.backends.curl_streaming")
local log = require("ask-openai.logs.logger").predictions()

---@class OaiCompletionsMiddle : CurlMiddle
local M = {}

---@param body table
---@param base_url string
---@param frontend StreamingFrontend
---@return LastRequest?
function M.curl_for(body, base_url, frontend)
    local url = base_url .. "/v1/completions"

    -- FYI! this appears vestigial... b/c I am using oai_chat for BOTH /v1/completions and /v1/chat/completions endpoints (and I don't swap this module in, I only change the URL/prompt)
    -- TODO can I get rid of this module and simplify oai_chat?
    -- I am really happen w/ llama-server at this point...
    --   TODO no reason for ollama any more so let's cleanup the code accordingly

    if body.tools ~= nil then
        error("tool use was requested, but this backend " .. url .. " does not support tools")
        return nil
    end

    ---@type ExtractGeneratedTextFunction
    local function extract_generated_text(choice)
        if choice == nil or choice.text == nil then
            -- just skip if no (first) choice or no text on it (i.e. last SSE is often timing only)
            return ""
        end
        return choice.text
    end

    return curl.reusable_curl_seam(body, url, frontend, extract_generated_text, M)
end

M.terminate = curl.terminate

return M
