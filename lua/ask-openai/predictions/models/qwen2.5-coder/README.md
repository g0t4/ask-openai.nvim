
Many parameters to ollama cannot be passed via API when using `/v1/completions`
So, create custom models tuned to my use case

Docs: https://github.com/ollama/ollama/blob/main/docs/modelfile.md

- `num_ctx` will default to ridiculously low values and truncate my FIM prompts...


```sh

# FYI show current modelfile:
ollama show --modelfile qwen2.5-coder:7b-instruct-q8_0

```
