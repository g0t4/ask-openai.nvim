local M = {}
local log = require("ask-openai.logs.logger").predictions()
local curl = require("ask-openai.backends.curl_streaming")

function M.curl_for(body, base_url, frontend)
    local url = base_url .. "/v1/chat/completions"
    return curl.reusable_curl_seam(body, url, frontend, M.parse_choice, M)
end

M.terminate = curl.terminate

-- *** output shape
--   FYI largely the same as for /v1/completions, except the message/delta under choices
--
--  created, id, model, object, system_fingerprint, usage
--  choices:
--    finish_reason:
--    index:
--    logprobs:
--
--    # stream only:
--    # https://platform.openai.com/docs/api-reference/chat-streaming
--    delta:
--      content: string
--      role: string
--      refusal: string
--      tool_calls: (formerly function_calls) ** vllm/ollama may use function_calls
--        function:
--          arguments:
--          name:
--        id:
--        type:
--        FYI means single tool calls dont span deltas? though IIAC still can do multiple across deltas
--
--    # sync only:
--    message:
--      refusal: string
--      content: string
--      role: string
--      annotations: [objects]
--      audio:
--      tool_calls: (same as in delta)

-- *** ollama /v1/chat/completions
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

-- * differs vs /v1/completions endpoint
function M.parse_choice(choice)
    -- TODO reasoning if already extracted?
    -- choice.delta.reasoning?/thinking? ollama splits this out, IIUC LM Studio does too... won't work if using harmony format with gpt-oss and its not parsed

    if choice.delta == nil or choice.delta.content == nil or choice.delta.content == vim.NIL then
        log:warn("WARN - unexpected, no delta in completion choice, what gives?!")
        return ""
    end
    return choice.delta.content
end

return M
