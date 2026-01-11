## old model notes in AskQuestion

taken from QuestionsFrontend right before sending a new question thread
**put notes here instead of bloating the code**

```lua
    ---@type ChatParams
    local qwen25_body_overrides = ChatParams:new({
        messages = messages,
        -- avoid num_ctx (s/b set server side), instead use max_tokens to cap request:
        max_tokens = 20000, -- PRN what level for rewrites?
        -- temperature = ?
    })

        -- model = "qwen2.5-coder:7b-instruct-q8_0", -- btw -base- does terrible here :) -- instruct works at random... seems to be a discrepency in published template and what it was actually trained with? (for tool calls)
        --
        -- * qwen3 related
        -- model = "qwen3:8b", -- btw as of Qwen3, no tag == "-instruct", and for base you'll use "-base" # VERY HAPPY WITH THIS MODEL FOR CODING TOO!
        -- model = "qwen3-coder:30b-a3b-q4_K_M",
        -- model = "qwen3-coder:30b-a3b-q8_0",
        -- model = "huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M",
        --
        -- model = "gemma3:12b-it-q8_0", -- btw -base- does terrible here :)
        -- temperature = 0.2, -- TODO what temp?
        -- model = "huggingface.co/lmstudio-community/openhands-lm-32b-v0.1-GGUF:latest", -- qwen fine tuned for SWE ... not doing well... same issue as qwen2.5-coder
    -- local body = agentica.DeepCoder.build_chat_body(system_prompt, user_message)
```

## context size

- avoid setting num_ctx (or similar)
  - set this on server (i.e. --ctx-size flag) and let max_tokens dictate ceiling within --ctx-size
- ollama, be careful w/ `num_ctx`, can't set it with OpenAI compat endpoints (whereas can pass with /api/generate)
  - SEE NOTES about how to set this with env vars / Modelfile instead that can work with openai endpoints (don't have to use /api/generate to fix this issue)
  - review start logs for n_ctx and during completion it warns if truncated prompt:
    - level=WARN source=runner.go:131 msg="truncating input prompt" limit=8192 prompt=10552 keep=4 new=8192

## /v1/completions no longer makes sense with ChatThread in AskToolUse/AskQuestion

- FYI not going to support /v1/completions anymore...
  - not until I have a specific need to use it
  - would need to manually format the prompt with a template or otherwise
    - including tool use instructions and parsing response for tool_calls, from scratch!
  - thus /v1/chat/completions exclusively makes sense
- if anything I could add support for /api/chat
  - i.e. using `ApiChatThread` that has a different `next_body()`...

Previously I used this when it was single turn Question/Answer:

local qwen_legacy_body = {
    model = "qwen2.5-coder:7b-instruct-q8_0", -- btw -base- does terrible here :)
    prompt = system_prompt .. "\n" .. user_message,
}


