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
