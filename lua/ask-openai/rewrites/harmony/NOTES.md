## vim.NIL on first delta?

TODO IS THIS AN ISSUE? I can skip for sure just curious... is this something to do with stripping out some of the tags?

choice object from logs:

```json
[TRACE] on_stdout data: data: {"choices":[{"finish_reason":null,"index":0,"delta":{"role":"assistant","content":null}}],"created":1754523863,"id":"chatcmpl-X6urH4f6JOotPwco2EgcgeoM6ZWup59u","model":"gpt-oss:20b","system_fingerprint":"b6097-9515c613","object":"chat.completion.chunk"}

{
  delta = {
    content = vim.NIL,
    role = "assistant"
  },
  finish_reason = vim.NIL,
  index = 0
}
```

AND is this why the end is empty for delta too!? NOTICE `"delta":{}` below:

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
