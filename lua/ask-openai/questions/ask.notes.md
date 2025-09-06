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


