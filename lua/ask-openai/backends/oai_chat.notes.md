## OpenAI compatible /v1/chat/completions endpoint

-- docs:
--   https://platform.openai.com/docs/api-reference/chat
--   https://docs.vllm.ai/en/stable/serving/openai_compatible_server.html#chat-api
--   https://github.com/ollama/ollama/blob/main/docs/openai.md#v1chatcompletions
--
-- *** input parameters supported /v1/chat/completions
--
-- messages[]
-- model
-- max_tokens (deprecated, really just doesn't work with reasoning models, doesn't work for o1 models... why did they do this? theyliterally renamed the option and made new models not work with old one?!)
--    max_completion_tokens (set max tokens including reasoning tokens)
--
-- stop
-- seed, temperature, top_p, n, frequency_penalty, presence_penalty
-- reasoning_effort
-- response_format
-- prediction { content, type } -- for spec decoding IIAC
--
-- parallel_tool_calls: default true
-- tool_choice (none, auto, required) -- whether or not the model can/should use tools
-- tools




## ** output shape
--   ******* FYI largely the same as for /v1/completions, except the message/delta under choices
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

