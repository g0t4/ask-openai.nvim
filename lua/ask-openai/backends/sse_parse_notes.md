## qwen2.5-coder + ollama -- completion chunk - /v1/chat/completions streaming

```json
{
  "id": "chatcmpl-768",
  "object": "chat.completion.chunk",
  "created": 1744445346,
  "model": "qwen2.5-coder:7b-instruct-q8_0",
  "system_fingerprint": "fp_ollama",
  "choices": [
    {
      "index": 0,
      "delta": {
        "role": "assistant",
        "content": "My name is Ben Dover. How can I help you today?"
      },
      "finish_reason": "stop"
    }
  ]
}
```
## qwen2.5-coder + ollama -- tool use - /v1/chat/completions streaming

TODO can I bait qwen into a parallel tool request?
   ollama has tool_call(s) from model... does qwen support parallel tool requests?


BTW there were no previous SSEs before these two:

First, we have a tool request (IIAC can be multiple of these across chunks):
```json
{
  "id": "chatcmpl-838",
  "object": "chat.completion.chunk",
  "created": 1744438886,
  "model": "qwen2.5-coder:7b-instruct-q8_0",
  "system_fingerprint": "fp_ollama",
  "choices": [
    {
      "index": 0,
      "delta": {
        "role": "assistant",
        "content": "",
        "tool_calls": [
          {
            "id": "call_hk81qg8b",
            "index": 0,
            "type": "function",
            "function": {
              "name": "run_command",
              "arguments": "{\"command\":\"ls -la\"}"
            }
          }
        ]
      },
      "finish_reason": null
    }
  ]
}

```

Then model asks for tool results by setting finish_reason=tool_calls
```json
{
  "id": "chatcmpl-838",
  "object": "chat.completion.chunk",
  "created": 1744438886,
  "model": "qwen2.5-coder:7b-instruct-q8_0",
  "system_fingerprint": "fp_ollama",
  "choices": [
    {
      "index": 0,
      "delta": {
        "role": "assistant",
        "content": ""
      },
      "finish_reason": "tool_calls"
    }
  ]
}
```
