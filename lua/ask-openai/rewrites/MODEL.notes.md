## groq.com

```lua
local base_url = "https://api.groq.com/openai"
model = "openai/gpt-oss-20b", -- 1000 tokens/sec
model = "openai/gpt-oss-120b", -- 500 tokens/sec
```

# Model notes for rewrites / questions (not completions)

         model = "qwen2.5-coder:7b-instruct-q8_0",

         * qwen3 related
         model = "qwen3:8b", -- btw as of Qwen3, no tag == "-instruct", and for base you'll use "-base" # VERY HAPPY WITH THIS MODEL FOR CODING TOO!
         model = "qwen3-coder:30b-a3b-q4_K_M",
         model = "qwen3-coder:30b-a3b-q8_0",
         model = "huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M",

         model = "deepseek-r1:8b-0528-qwen3-q8_0", -- /nothink doesn't work :(

         model = "gemma3:12b-it-q8_0",
        -- local body = agentica.DeepCoder.build_chat_body(system_prompt, user_message)
