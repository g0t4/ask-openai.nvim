
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


