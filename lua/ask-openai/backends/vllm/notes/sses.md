# legacy completions endpoints

it is ok to discard these notes, just kept in case it helps, i.e. find who does what with SSE fields

## vllm notes

- vllm /v1/completions:
    - https://docs.vllm.ai/en/stable/serving/openai_compatible_server.html#completions-api
- vllm FIM discussions:
    - https://github.com/vllm-project/vllm/pull/11713

- AFAICT, vllm doesn't support prompt(prefix)/suffix params, instead must be fully raw always
    - their docs explicitly state that they don't support "suffix"
    - raw = true, -- bypass templates (only /api/generate, not /v1/completions)

## examples /api/generate:

```json
{
    "model": "qwen2.5-coder:3b",
    "created_at": "2025-01-26T11:24:56.1915236Z",
    "response": "\n",
    "done": false
}
```

DONE example:

```json
{
    "model": "qwen2.5-coder:3b",
    "created_at": "2025-01-26T11:24:56.2800621Z",
    "response": "",
    "done": true,
    "done_reason": "stop",
    "total_duration": 131193100,
    "load_duration": 16550700,
    "prompt_eval_count": 19,
    "prompt_eval_duration": 5000000,
    "eval_count": 12,
    "eval_duration": 106000000
}
```

## vllm /v1/completions responses:

middle completion:

```json
{
    "id": "cmpl-eec6b2c11daf423282bbc9b64acc8144",
    "object": "text_completion",
    "created": 1741824039,
    "model": "Qwen/Qwen2.5-Coder-3B",
    "choices": [
        {
            "index": 0,
            "text": "ob",
            "logprobs": null,
            "finish_reason": null,
            "stop_reason": null
        }
    ],
    "usage": null
}
```

final completion:

```json
{
    "id": "cmpl-06be557c45c24e458ea2e36d436faf60",
    "object": "text_completion",
    "created": 1741823318,
    "model": "Qwen/Qwen2.5-Coder-3B",
    "choices": [
        {
            "index": 0,
            "text": " and",
            "logprobs": null,
            "finish_reason": "length",
            "stop_reason": null
        }
    ],
    "usage": null
}
```

pretty print with vim:

```lua
Dump(vim.json.decode('{"id":"cmpl-06be557c45c24e458ea2e36d436faf60","object":"text_completion","created":1741823318,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":" and","logprobs":null,"finish_reason":"length","stop_reason":null}],"usage":null}')

{
     choices = {
         {
             finish_reason = "length",
             index = 0,
             logprobs = vim.NIL,
             stop_reason = vim.NIL,
             text = " and"
         }
     },
     created = 1741823318,
     id = "cmpl-06be557c45c24e458ea2e36d436faf60",
     model = "Qwen/Qwen2.5-Coder-3B",
     object = "text_completion",
     usage = vim.NIL
}
```
