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

    -- TODO detect which ExtractGeneratedTextFunction to use based on URL
    --   and for URL, set that like predictions and have logic activat eone of the two extract_generated_text alternatives
    --   FYI could have third ExtractGeneratedTextFunction ... one for non-openai /completions endpoint on llama-server
    --     => no choice so I'd have to change how this is activated... b/c right now  curl_streaming assumes .choices is set
    --     whereas with non-openai /completions it would just use top-level to get text (.content)

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
