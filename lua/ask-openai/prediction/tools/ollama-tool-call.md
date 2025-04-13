## ollama /api/chat with qwen2.5-coder

# request:
```sh
curl http://localhost:11434/api/chat -d '{
   "model": "qwen2.5-coder:7b-instruct-q8_0",
   "messages":  [ { "role": "user", "content": "You are a helpful assistant. Use the tool `run_command` to check how much disk space is free." }],
   "tools": [
     {
       "name": "run_command",
       "description": "Run a shell command and return its output.",
       "parameters": {
         "type": "object",
         "properties": {
           "command": { "type": "string", "description": "The shell command to run" }
         },
         "required": ["command"]
       }
     }
   ],
   "stream": false
 }'
```


# response:
```json
{
"model": "qwen2.5-coder:7b-instruct-q8_0",
"created_at": "2025-04-11T18:18:52.293545Z",
"message": {
 "role": "assistant",
 "content": "",
 "tool_calls": [
   {
     "function": {
       "name": "run_command",
       "arguments": {
         "command": "df -h"
       }
     }
   }
 ]
},
"done_reason": "stop",
"done": true,
"total_duration": 2347998750,
"load_duration": 19605625,
"prompt_eval_count": 155,
"prompt_eval_duration": 321024542,
"eval_count": 81,
"eval_duration": 2005950875
}
```


## ok 2.5-coder also has generated some crazy examples of not tool calls but looks close
makes me wonder if the vllm issue with 2.5-coder is maybe b/c the coder variant is not wise for tool use?
keep in mind I have that request for markdown at the top of the prompt.. that could cause some issues too...

[4.544]sec [TRACE] on_stdout data: data: {"id":"chatcmpl-783","object":"chat.completion.chunk","created":1744517081,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"```\nxml\n\u003ccommand\u003e\n  \u003crun_command\u003e\n    \u003ccommand\u003els -l\u003c/command\u003e\n  \u003c/run_command\u003e\n\u003c/command\u003e\n```"},"finish_reason":"stop"}]}
=>
```xml
<command>
  <run_command>
    <command>ls -l</command>
  </run_command>
</command>
```

[13.184]sec [TRACE] on_stdout data: data: {"id":"chatcmpl-470","object":"chat.completion.chunk","created":1744517090,"model":"qwen2.5-coder:7b-instruct-q8_0","system_fingerprint":"fp_ollama","choices":[{"index":0,"delta":{"role":"assistant","content":"\u003crun_command command=\"ls -l\" /\u003e"},"finish_reason":"stop"}]}
=>
<run_command command="ls -l" />



