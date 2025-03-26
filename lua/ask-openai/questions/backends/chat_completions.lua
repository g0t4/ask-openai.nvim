local M = {}
local log = require("ask-openai.prediction.logger").predictions()

-- TODO move body formatter here? and other methods like with prediction backends?
-- TODO! use for code rewriting to be streaming too => move this to a diff folder for chat/completions backends, not just questions backend

function M.process_sse(data)
    -- SSE = Server-Sent Event
    -- split on lines first (each SSE can have 0+ "event" - one per line)

    local chunk = nil -- combine all chunks into one string and check for done
    local done = false
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
            if choice.finish_reason then --  no finish reason? not sure if ever happens... keep going...
                local finish_reason = choice.finish_reason
                done = true
                if finish_reason ~= "stop" then
                    log:warn("WARN - unexpected /v1/chat/completions finish_reason: ", finish_reason, " do you need to handle this too?")
                    -- ok for now to continue too
                end
            end
            chunk = (chunk or "") .. choice.delta.content
        else
            log:warn("SSENEW json parse failed for ss_event: ", ss_event)
        end
    end
    return chunk, done
end

return M
