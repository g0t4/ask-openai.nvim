## OpenAI compatible /v1/completions (legacy) endpoint

-- aka "legacy" completions endpoint
-- no chat history concept
--   good for single turn requests
--   can easily be used for back and forth if you are summarizing previous messages into the next prompt
-- raw prompt typically is reason to use this, i.e. FIM
-- can get confusing if not "raw" and the backend applies templates that are shipped w/ the model...
--   make sure you understand each model's template and appropriately build the request body

-- *** input parameters supported /v1/chat/completions
-- prompt (entire message)
-- max_tokens
-- suffix (IIRC not avail with vllm, ollama uses for FIM except if raw=true, )
-- stop
-- seed, temperature, top_p, n, frequency_penalty, presence_penalty

-- *** output shape
--   FYI largely the same as for /v1/chat/completions, except the generated text
--  created, id, model, object, system_fingerprint, usage
--  choices
--    finish_reason: string  # vllm seems to use stop_reason (see below)
--    index: integer
--    logprobs: obj/null
--    text: string    (*** this is the only difference vs chat)

-- *** vllm /v1/completions responses:
--  middle completion:
--   {"id":"cmpl-eec6b2c11daf423282bbc9b64acc8144","object":"text_completion","created":1741824039,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":"ob","logprobs":null,"finish_reason":null,"stop_reason":null}],"usage":null}
--
--  final completion:
--   {"id":"cmpl-06be557c45c24e458ea2e36d436faf60","object":"text_completion","created":1741823318,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":" and","logprobs":null,"finish_reason":"length","stop_reason":null}],"usage":null}
--    pretty print with vim:
--    :Dump(vim.json.decode('{"id":"cmpl-06be557c45c24e458ea2e36d436faf60","object":"text_completion","created":1741823318,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":" and","logprobs":null,"finish_reason":"length","stop_reason":null}],"usage":null}')
-- {
--   choices = { {
--       finish_reason = "length",
--       index = 0,
--       logprobs = vim.NIL,
--       stop_reason = vim.NIL,
--       text = " and"
--     } },
--   created = 1741823318,
--   id = "cmpl-06be557c45c24e458ea2e36d436faf60",
--   model = "Qwen/Qwen2.5-Coder-3B",
--   object = "text_completion",
--   usage = vim.NIL
-- }

