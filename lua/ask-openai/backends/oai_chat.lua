local M = {}
local log = require("ask-openai.logs.logger").predictions()
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

    if choice.delta == nil then -- or choice.delta.content == nil or choice.delta.content == vim.NIL then
        log:warn("WARN - unexpected, no delta in completion choice, what gives?!")
        return ""
    end
    return choice.delta.content
end

return M
