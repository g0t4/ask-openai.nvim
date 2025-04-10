local M = {}
local log = require("ask-openai.prediction.logger").predictions()
local curl = require("ask-openai.backends.curl_streaming")

-- FYI this is intended for use w/ instruct models

-- docs:
--   https://platform.openai.com/docs/api-reference/chat
--   https://docs.vllm.ai/en/stable/serving/openai_compatible_server.html#chat-api
--   https://github.com/ollama/ollama/blob/main/docs/openai.md#v1chatcompletions
--
-- *** input parameters supported /v1/chat/completions
-- FYI parameters are perpendicular to this backend abstraction... a function of frontend really... so don't try to set these here
--   obviously "stream: true" is universal here
--   backend can enforce required params and validate optional params, if needed
--
-- messages[]
-- model
-- max_tokens (deprecated, really just doesn't work with reasoning models, doesn't work for o1 models... why did they do this? theyliterally renamed the option and made new models not work with old one?!)
--    max_completion_tokens (set max tokens including reasoning tokens)
--
-- stop
-- stream
-- seed, temperature, top_p, n, frequency_penalty, presence_penalty
-- reasoning_effort
-- response_format
-- prediction { content, type } -- for spec decoding IIAC
--
-- *** tool use:
--   probably will build a wrapper around this oai_completions endpoint... for tool use too
--   can still stream reasponse and have automatic tool use in parallel with first response even:
--
-- parallel_tool_calls: default true
-- tool_choice (none, auto, required) -- whether or not the model can/should use tools
-- tools


function M.curl_for(body, base_url, frontend)
    local url = base_url .. "/v1/chat/completions"
    return curl.reusable_curl_seam(body, url, frontend, M.sse_to_chunk)
end

function M.sse_to_chunk(data)
    -- SSE = Server-Sent Event
    -- split on lines first (each SSE can have 0+ "event" - one per line)

    local chunk = nil -- combine all chunks into one string and check for done
    local done = false
    local finish_reason = nil
    for ss_event in data:gmatch("[^\r\n]+") do
        if ss_event:match("^data:%s*%[DONE%]$") then
            -- done, courtesy last event... mostly ignore b/c finish_reason already comes on the prior SSE
            return chunk, true
        end

        --  strip leading "data: " (if present)
        local event_json = ss_event
        if ss_event:sub(1, 6) == "data: " then
            event_json = ss_event:sub(7)
        end
        local success, parsed = pcall(vim.json.decode, event_json)

        -- *** examples /v1/chat/completions
        -- {"id":"chatcmpl-209","object":"chat.completion.chunk","created":1743021818,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"."},"finish_reason":null}]}
        -- {
        --   "id": "chatcmpl-209",
        --   "object": "chat.completion.chunk",
        --   "created": 1743021818,
        --   "model": "qwen2.5-coder:7b-instruct-q8_0",
        --   "system_fingerprint": "fp_ollama",
        --   "choices": [
        --     {
        --       "index": 0,
        --       "delta": {
        --         "role": "assistant",
        --         "content": "."
        --       },
        --       "finish_reason": null
        --     }
        --   ]
        -- }
        -- {"id":"chatcmpl-209","object":"chat.completion.chunk","created":1743021818,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"stop"}]}
        if success and parsed and parsed.choices and parsed.choices[1] then
            local choice = parsed.choices[1]
            finish_reason = choice.finish_reason
            if finish_reason ~= nil and finish_reason ~= vim.NIL then
                done = true
                if finish_reason ~= "stop" and finish_reason ~= "length" then
                    log:warn("WARN - unexpected /v1/chat/completions finish_reason: ", finish_reason, " do you need to handle this too?")
                end
            end
            if choice.delta == nil or choice.delta.content == nil then
                log:warn("WARN - unexpected, no delta.content in completion choice, do you need to add special logic to handle this?")
            end
            chunk = (chunk or "") .. choice.delta.content
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    -- TODO test passing back finish_reason (i.e. for an empty response though that shouldn't happen when asking a question)
    return chunk, done, finish_reason
end

return M
