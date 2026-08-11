#!/usr/bin/env fish

curl -X POST http://paxy:8016/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "user", "content": "What time is it?" }
    ],
    "temperature": 1.0,
    "top_p": 1.0,
    "max_tokens": 300,
    "chat_template_kwargs": {
      "reasoning_strength": "low"
    }
  }' | jq
