## last SSE llama-server fails to "parse"

[WARN ] WARN - unexpected, no delta in completion choice, what gives?!
[WARN ] SSE json parse failed for ss_event: data: {"choices":[],"created":1756191041,"id":"chatcmpl-CQC9ww0KtsZGzo41Ldp1liJHPRJ6zV29","model":"","system_fingerprint":"b6271-dfd9b5f6","object":"chat.completion.chunk","usage":{"completion_tokens":409,"prompt_tokens":515,"total_tokens":924},"timings":{"prompt_n":1,"prompt_ms":22.812,"prompt_per_token_ms":22.812,"prompt_per_second":43.836577240049095,"predicted_n":409,"predicted_ms":2222.731,"predicted_per_token_ms":5.434550122249389,"predicted_per_second":184.00787139784345}}

## groq.com

```lua
local base_url = "https://api.groq.com/openai"
model = "openai/gpt-oss-20b", -- 1000 tokens/sec
model = "openai/gpt-oss-120b", -- 500 tokens/sec
```

## misc

```lua
model = "qwen2.5-coder:7b-instruct-q8_0",

-- * qwen3 related
model = "qwen3:8b", -- btw as of Qwen3, no tag == "-instruct", and for base you'll use "-base" # VERY HAPPY WITH THIS MODEL FOR CODING TOO!
model = "qwen3-coder:30b-a3b-q4_K_M",
model = "qwen3-coder:30b-a3b-q8_0",
model = "huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M",

model = "deepseek-r1:8b-0528-qwen3-q8_0", -- /nothink doesn't work :(

model = "gemma3:12b-it-q8_0",
-- local body = agentica.DeepCoder.build_chat_body(system_prompt, user_message)
```
