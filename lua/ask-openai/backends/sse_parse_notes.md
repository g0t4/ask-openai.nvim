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

### qwen made a parallel tool call! first `ls` then `ls -al` almost like I might forget to list all and so he asked for it a second time

models s/b able to cancel tool calls! tool_cancels!
though this would suggest that the model doesn't finish and remains there waiting and able to say more stuff at any time... which actually can make sense... a low-power mode where the model thinks a bit more about what he asked for and if it was the wrong thing! and so yeah... say NO I meant!


```sh
ls
# data: {"id":"chatcmpl-18","object":"chat.completion.chunk","created":1744446075,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"","tool_calls":[{"id":"call_wteop8bt","index":0,"type":"function","function":{"name":"run_command","arguments":"{\"command\":\"ls\"}"}}]},"finish_reason":null}]}

ls -l
# data: {"id":"chatcmpl-18","object":"chat.completion.chunk","created":1744446075,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"","tool_calls":[{"id":"call_rk2xye1l","index":1,"type":"function","function":{"name":"run_command","arguments":"{\"command\":\"ls -l\"}"}}]},"finish_reason":null}]}

# done, waiting on tool_calls
# data: {"id":"chatcmpl-18","object":"chat.completion.chunk","created":1744446075,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"tool_calls"}]}
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
