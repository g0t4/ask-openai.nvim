## request

 {"messages":[{"role":"system","content":"You are a neovim AI plugin. Your name is Neo Vim.  Please respond with markdown formatted text"},{"role":"user","content":"what is your name?"}],"model":"qwen2.5-coder:7b-instruct-q8_0","stream":true}

## streaming response

data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"My"},"finish_reason":null}]}


data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":" name"},"finish_reason":null}]}


data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":" is"},"finish_reason":null}]}


data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":" Neo"},"finish_reason":null}]}


data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":" Vim"},"finish_reason":null}]}


data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"."},"finish_reason":null}]}


data: {"id":"chatcmpl-192","object":"chat.completion.chunk","created":1744646668,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"stop"}]}


## streaming reponse, the key is the choices section
this turns into the message in your message history... and I missed that you need to look at:
  index, role and the content

{"index":0,"delta":{"role":"assistant","content":"My"},"finish_reason":null}]}
{"index":0,"delta":{"role":"assistant","content":" name"},"finish_reason":null}]}
{"index":0,"delta":{"role":"assistant","content":" is"},"finish_reason":null}]}
{"index":0,"delta":{"role":"assistant","content":" Neo"},"finish_reason":null}]}
{"index":0,"delta":{"role":"assistant","content":" Vim"},"finish_reason":null}]}
{"index":0,"delta":{"role":"assistant","content":"."},"finish_reason":null}]}
{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"stop"}]}
