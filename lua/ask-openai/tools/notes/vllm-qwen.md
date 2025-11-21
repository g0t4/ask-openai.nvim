
## vllm logs (generated prompt)

INFO 04-12 22:07:44 [logger.py:39] Received request chatcmpl-d0c68c86be0641129cffa5053c0c217e: prompt: '<|im_start|>system\nYour name is Ben Dover, you are a neovim AI plugin that answers questions. Please respond with markdown formatted text, that will be presented in a floating window.\n\n# Tools\n\nYou may call one or more functions to assist with the user query.\n\nYou are provided with function signatures within <tools></tools> XML tags:\n<tools>\n{"type": "function", "function": {"name": "run_command", "description": null, "parameters": {"properties": {"cwd": {"description": "Current working directory, leave empty in most cases", "type": "string"}, "command": {"description": "Command with args", "type": "string"}}, "required": ["command"], "type": "object"}}}\n{"type": "function", "function": {"name": "run_script", "description": null, "parameters": {"properties": {"interpreter": {"description": "Command with arguments. Script will be piped to stdin. Examples: bash, fish, zsh, python, or: bash --norc", "type": "string"}, "script": {"description": "Script to run", "type": "string"}, "cwd": {"description": "Current working directory", "type": "string"}}, "required": ["script"], "type": "object"}}}\n</tools>\n\nFor each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\n<tool_call>\n{"name": <function-name>, "arguments": <args-json-object>}\n</tool_call><|im_end|>\n<|im_start|>user\nplease list files<|im_end|>\n<|im_start|>assistant\n', params: SamplingParams(n=1, presence_penalty=0.0, frequency_penalty=0.0, repetition_penalty=1.05, temperature=0.7, top_p=0.8, top_k=20, min_p=0.0, seed=None, stop=[], stop_token_ids=[], bad_words=[], include_stop_str_in_output=False, ignore_eos=False, max_tokens=32442, min_tokens=0, logprobs=None, prompt_logprobs=None, skip_special_tokens=True, spaces_between_special_tokens=True, truncate_prompt_tokens=None, guided_decoding=None, extra_args=None), prompt_token_ids: None, lora_request: None, prompt_adapter_request: None.
INFO:     - "POST /v1/chat/completions HTTP/1.1" 200 OK
INFO 04-12 22:07:44 [engine.py:289] Added request chatcmpl-d0c68c86be0641129cffa5053c0c217e.


## tailing my ask log

[55.464]sec [WARN] curl args: --fail-with-body -sSL --no-buffer -X POST http://build21:8000/v1/chat/completions -H Content-Type: application/json -d {"messages": [{"role": "system", "content": "Your name is Ben Dover, you are a neovim AI plugin that answers questions. Please respond with markdown formatted text, that will be presented in a floating window."}, {"role": "user", "content": "please list files"}], "model": "", "stream": true, "tools": [{"function": {"name": "run_command", "parameters": {"properties": {"cwd": {"description": "Current working directory, leave empty in most cases", "type": "string"}, "command": {"description": "Command with args", "type": "string"}}, "required": ["command"], "type": "object"}}, "type": "function"}, {"function": {"name": "run_script", "parameters": {"properties": {"interpreter": {"description": "Command with arguments. Script will be piped to stdin. Examples: bash, fish, zsh, python, or: bash --norc", "type": "string"}, "script": {"description": "Script to run", "type": "string"}, "cwd": {"description": "Current working directory", "type": "string"}}, "required": ["script"], "type": "object"}}, "type": "function"}]}
[55.491]sec [TRACE] {"messages":[{"role":"system","content":"Your name is Ben Dover, you are a neovim AI plugin that answers questions. Please respond with markdown formatted text, that will be presented in a floating window."},{"role":"user","content":"please list files"}],"model":"","stream":true,"tools":[{"function":{"name":"run_command","parameters":{"properties":{"cwd":{"description":"Current working directory, leave empty in most cases","type":"string"},"command":{"description":"Command with args","type":"string"}},"required":["command"],"type":"object"}},"type":"function"},{"function":{"name":"run_script","parameters":{"properties":{"interpreter":{"description":"Command with arguments. Script will be piped to stdin. Examples: bash, fish, zsh, python, or: bash --norc","type":"string"},"script":{"description":"Script to run","type":"string"},"cwd":{"description":"Current working directory","type":"string"}},"required":["script"],"type":"object"}},"type":"function"}]}
[55.491]sec [TRACE]
[55.491]sec [TRACE]
[55.529]sec [TRACE] on_stdout data: data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}


[55.615]sec [TRACE] on_stdout data: data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"id":"chatcmpl-tool-ca99dda515524c6abe47d1ea22813507","type":"function","index":0,"function":{"name":"run_command"}}]},"logprobs":null,"finish_reason":null}]}


[55.690]sec [TRACE] on_stdout data: data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"command\": \""}}]},"logprobs":null,"finish_reason":null}]}


[55.701]sec [TRACE] on_stdout data: data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"ls"}}]},"logprobs":null,"finish_reason":null}]}


[55.711]sec [TRACE] on_stdout data: data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]},"logprobs":null,"finish_reason":null}]}


[55.733]sec [TRACE] on_stdout data: data: {"id":"chatcmpl-d0c68c86be0641129cffa5053c0c217e","object":"chat.completion.chunk","created":1744513664,"model":"","choices":[{"index":0,"delta":{"content":""},"logprobs":null,"finish_reason":"tool_calls","stop_reason":null}]}

data: [DONE]


[55.733]sec [TRACE] on_stderr data: nil
[55.733]sec [TRACE] on_stdout data: nil
[55.733]sec [TRACE] on_exit code:0, signal:0
"chatcmpl-d0c68c86be0641129cffa5053c0c217e"


## vllm Qwen2.5-Coder (same as above but not working for tools):
Always returning tool call in markdown with json code block w correct tool call args!

INFO 04-12 22:21:22 [logger.py:39] Received request chatcmpl-25e19884c14d419ebc0e33590c514200: prompt: '<|im_start|>system\nYour name is Ben Dover, you are a neovim AI plugin that answers questions. Please respond with markdown formatted text, that will be presented in a floating window.\n\n# Tools\n\nYou may call one or more functions to assist with the user query.\n\nYou are provided with function signatures within <tools></tools> XML tags:\n<tools>\n{"type": "function", "function": {"name": "run_script", "description": null, "parameters": {"properties": {"interpreter": {"description": "Command with arguments. Script will be piped to stdin. Examples: bash, fish, zsh, python, or: bash --norc", "type": "string"}, "script": {"description": "Script to run", "type": "string"}, "cwd": {"description": "Current working directory", "type": "string"}}, "required": ["script"], "type": "object"}}}\n{"type": "function", "function": {"name": "run_command", "description": null, "parameters": {"properties": {"cwd": {"description": "Current working directory, leave empty in most cases", "type": "string"}, "command": {"description": "Command with args", "type": "string"}}, "required": ["command"], "type": "object"}}}\n</tools>\n\nFor each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\n<tool_call>\n{"name": <function-name>, "arguments": <args-json-object>}\n</tool_call><|im_end|>\n<|im_start|>user\nplease list files<|im_end|>\n<|im_start|>assistant\n', params: SamplingParams(n=1, presence_penalty=0.0, frequency_penalty=0.0, repetition_penalty=1.1, temperature=0.7, top_p=0.8, top_k=20, min_p=0.0, seed=None, stop=[], stop_token_ids=[], bad_words=[], include_stop_str_in_output=False, ignore_eos=False, max_tokens=32442, min_tokens=0, logprobs=None, prompt_logprobs=None, skip_special_tokens=True, spaces_between_special_tokens=True, truncate_prompt_tokens=None, guided_decoding=None, extra_args=None), prompt_token_ids: None, lora_request: None, prompt_adapter_request: None.
INFO:     "POST /v1/chat/completions HTTP/1.1" 200 OK
INFO 04-12 22:21:22 [engine.py:289] Added request chatcmpl-25e19884c14d419ebc0e33590c514200.



## ollama qwen2.5-coder-7b-instruct filled in prompt (working fine to gen tool calls):
# TODO COMPARE tool portion of prompt between the two systems
#   OTHER POSSIBILITY is vllm is buggy when serving coder? I swear I have much better luck with predicitons in ollama than vllm,
SAMPLING PARAMS?
TEMPLATES?
bugs in running models (in vllm)?

time=2025-04-12T22:37:35.110-05:00 level=DEBUG source=routes.go:1522 msg="chat request" images=0 prompt="<|im_start|>system\nYour name is Ben Dover, you are a neovim AI plugin.\n\n\n# Tools\n\nYou may call one or more functions to assist with the user query.\n\nYou are provided with function signatures within <tools></tools> XML tags:\n<tools>\n{\"type\": \"function\", \"function\": {\"name\":\"run_script\",\"description\":\"\",\"parameters\":{\"type\":\"object\",\"required\":[\"script\"],\"properties\":{\"cwd\":{\"type\":\"string\",\"description\":\"Current working directory\"},\"interpreter\":{\"type\":\"string\",\"description\":\"Command with arguments. Script will be piped to stdin. Examples: bash, fish, zsh, python, or: bash --norc\"},\"script\":{\"type\":\"string\",\"description\":\"Script to run\"}}}}}\n{\"type\": \"function\", \"function\": {\"name\":\"run_command\",\"description\":\"\",\"parameters\":{\"type\":\"object\",\"required\":[\"command\"],\"properties\":{\"command\":{\"type\":\"string\",\"description\":\"Command with args\"},\"cwd\":{\"type\":\"string\",\"description\":\"Current working directory, leave empty in most cases\"}}}}}\n</tools>\n\nFor each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\n<tool_call>\n{\"name\": <function-name>, \"arguments\": <args-json-object>}\n</tool_call><|im_end|>\n<|im_start|>user\nplease list files<|im_end|>\n<|im_start|>assistant\n"


