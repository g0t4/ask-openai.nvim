local M = {}
local log = require("ask-openai.prediction.logger").predictions()

-- docs:
-- /chat/completions: https://docs.vllm.ai/en/stable/serving/openai_compatible_server.html#chat-api

-- FYI this is intended for use w/ instruct models
--  TODO! determine if this can be generalized...
--  TODO TEST THIS WITH VLLM's /chat/completions
--  TODO TEST W/ ollama too (IIRC I wrote this to work with ollama initially)
--  TODO test with OpenAI too

function M.process_sse(data)
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
