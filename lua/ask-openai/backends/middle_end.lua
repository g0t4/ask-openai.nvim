local log = require("ask-openai.logs.logger").predictions()
local curl = require("ask-openai.backends.curl_streaming")

--- TODO! remove this "middle_end", it isn't needed anymore
---
---@class MiddleEnd
---@field terminate function(request: LastRequest, cb: function())
local M = {}

---@enum CompletionsEndpoints
M.CompletionsEndpoints = {
    completions = "/completions",

    -- OpenAI compatible:
    v1_completions = "/v1/completions",
    v1_chat = "/v1/chat/completions",
}

---@param body table
---@param base_url string
---@param endpoint CompletionsEndpoints
---@param frontend StreamingFrontend
---@return LastRequest?
function M.curl_for(body, base_url, endpoint, frontend)
    local url = base_url .. endpoint

    -- * /completions  CompletionsEndpoints.completions
    --   3rd ExtractGeneratedTextFunction for non-openai /completions endpoint on llama-server
    --     => no sse.choice so I'd have to change how M.on_line_or_lines works to not assume sse.choices
    --     whereas with non-openai /completions it would just use top-level to get text (.content)

    ---@type ExtractGeneratedTextFunction
    local function extract_generated_text_v1_completions(choice)
        --- * /v1/completions
        if choice == nil or choice.text == nil then
            -- just skip if no (first) choice or no text on it (i.e. last SSE is often timing only)
            return ""
        end
        return choice.text
    end

    ---@type ExtractGeneratedTextFunction
    local function extract_generated_text_v1_chat(choice)
        --- * /v1/chat/completions
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

    local use_extract_generated_text
    if endpoint == M.CompletionsEndpoints.v1_chat then
        use_extract_generated_text = extract_generated_text_v1_chat
    elseif endpoint == M.CompletionsEndpoints.v1_completions then
        use_extract_generated_text = extract_generated_text_v1_completions
    else
        -- TODO CompletionsEndpoints.completions /completions for 3rd ExtractGeneratedTextFunction
        error("Not yet implemented: " .. endpoint)
    end

    return curl.reusable_curl_seam(body, url, frontend, use_extract_generated_text)
end

M.terminate = curl.terminate

return M
