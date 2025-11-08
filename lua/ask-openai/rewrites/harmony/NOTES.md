## vim.NIL on first delta

First SSE has content == vim.NIL b/c in JSON "content": null (likely b/c it is just reporting role as "assistant")... NBD ignore this
-- data: {"choices":[{"finish_reason":null,"index":0,"delta":{"role":"assistant","content":null}}],"created":1762593253,"id":"chatcmpl-DHvcEyFobkuV4Xu1QSYo4bqNv18TDqaA","model":"gpt-oss:120b","system_fingerprint":"b6881-8b11deea4","object":"chat.completion.chunk"}
2+ SSEs are thinking so content field is completely missing in JSON, thus content == nil, again ignore that too
-- data: {"choices":[{"finish_reason":null,"index":0,"delta":{"reasoning_content":"We"}}],"created":1762593253,"id":"chatcmpl-DHvcEyFobkuV4Xu1QSYo4bqNv18TDqaA","model":"gpt-oss:120b","system_fingerprint":"b6881-8b11deea4","object":"chat.completion.chunk"}

? AND is this why the end is empty for delta too!? NOTICE `"delta":{}` below:

```json
{"choices":[{"finish_reason":"stop","index":0,"delta":{}}],"created":1754524122,"id":"chatcmpl-yPk7z9nC22CofOlh100qQdHVEDMNYCb1","model":"gpt-oss:20b","system_fingerprint":"b6097-9515c613","object":"chat.completion.chunk","usage":{"completion_tokens":247,"prompt_tokens":1085,"total_tokens":1332},"timings":{"prompt_n":1085,"prompt_ms":203.378,"prompt_per_token_ms":0.18744516129032257,"prompt_per_second":5334.893646313762,"predicted_n":247,"predicted_ms":933.63,"predicted_per_token_ms":3.7798785425101213,"predicted_per_second":264.5587652496171}}
```

## \* llama-server (llama cpp)

<|channel|>analysis<|message|>User wrote "test". Likely just a test message. They might want ChatGPT to respond? We should respond politely. Maybe just say "Hello! How can I help?"<|start|>assistant<|channel|>final<|message|>Hello! 👋 How can I assist you today?

this assumes that in the original message you added <|start|>assistant

- and thus it continues right into the <|channel|> as start of response

here is what the COMPLETE output would look like:
https://cookbook.openai.com/articles/openai-harmony#example-output

However, <|end|> and <|return|> are both stripped by llama-server

- no idea why touch it at all if you are leaving most of it?!

## * TLDR parse as think tags idea:
- treat this sequence as the "<think>" tag
  <|channel|>analysis<|message|>
- treat this sequence as the "</think>" tag
  <|start|>assistant<|channel|>final<|message|>
- FYI seems like llama-cpp's chat app does this too:
    https://github.com/ggml-org/llama.cpp/blob/3db4da56/common/chat.cpp#L1323

## * gpt-oss:20b first stdout has two SSEs and first is only one parsed

[TRACE] on_stdout data: data: {"choices":[{"finish_reason":null,"index":0,"delta":{"role":"assistant","content":null}}],"created":1754544631,"id":"chatcmpl-5cW7mFM6xD9ZRdrIZBhnCZo8QvLru6aj","model":"gpt-oss:20b","system_fingerprint":"b6103-3db4da56","object":"chat.completion.chunk"}

data: {"choices":[{"finish_reason":null,"index":0,"delta":{"content":"<|channel|>"}}],"created":1754544631,"id":"chatcmpl-5cW7mFM6xD9ZRdrIZBhnCZo8QvLru6aj","model":"gpt-oss:20b","system_fingerprint":"b6103-3db4da56","object":"chat.completion.chunk"}

## * llama-server stats on last delta

```json
{
    "choices": [{ "finish_reason": "stop", "index": 0, "delta": {} }],
    "created": 1754585743,
    "id": "chatcmpl-2OrYcv4nD14KsYEcjDsTBuDAd6bEDOT2",
    "model": "gpt-oss:20b",
    "system_fingerprint": "b6103-3db4da56",
    "object": "chat.completion.chunk",
    "usage": {
        "completion_tokens": 332,
        "prompt_tokens": 892,
        "total_tokens": 1224
    },
    "timings": {
        "prompt_n": 721,
        "prompt_ms": 136.23,
        "prompt_per_token_ms": 0.18894590846047155,
        "prompt_per_second": 5292.520002936211,
        "predicted_n": 332,
        "predicted_ms": 1253.787,
        "predicted_per_token_ms": 3.7764668674698796,
        "predicted_per_second": 264.79776868000704
    }
}
```


## * tool use

```harmony
srv  update_chat_: Parsing chat message: <|channel|>analysis<|message|>We need to run a command to get current directory. Use 'pwd'. Use the run_command tool.<|start|>assistant<|channel|>commentary to=functions.run_command json<|message|>{"command":"pwd"}
Parsing input with format GPT-OSS: <|channel|>analysis<|message|>We need to run a command to get current directory. Use 'pwd'. Use the run_command tool.<|start|>assistant<|channel|>commentary to=functions.run_command json<|message|>{"command":"pwd"}
```

## ollama /v1/chat/completions endpoint

FYI this might be outdated, found this in code for parsing SSEs, and moved it here.

```json
// reasoning/thinking deltas (full message, all fields):
{
    "id":"chatcmpl-900","object":"chat.completion.chunk","created":1754453131,"model":"gpt-oss:20b","system_fingerprint":"fp_ollama",
    "choices":[{"index":0,"delta":{"role":"assistant","content":"","reasoning":"?"},"finish_reason":null}]
}
```json
// content deltas:
{ "choices":[{"index":0,"delta":{"role":"assistant","content":" }"},"finish_reason":null}]} }
{ "choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"stop"}]} }
```

