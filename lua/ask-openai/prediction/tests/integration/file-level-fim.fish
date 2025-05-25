#!/usr/bin/env fish

# get this from logs for ask-openai, in a real file

set request_body '{
  "prompt": "<|fim_prefix|>local M = {}\n\nfunction M.add(a, b)\n    return a + b\nend\n\n<|fim_suffix|>\n\n\nreturn M<|fim_middle|>",
  "options": {
    "num_ctx": 8192
  },
  "raw": true,
  "num_predict": 200,
  "stream": false,
  "model": "qwen2.5-coder:7b-base-q8_0"
}'

log_ --blue "## PROMPT"
echo $request_body | jq -r .prompt

# PRN use --dump-header to capture and analyze headers separately
set curl_command curl \
    -fsSL \
    --no-buffer \
    -H "Content-Type: application/json" \
    http://ollama:11434/api/generate \
    -d @-
# FYI STDERR not redirected, so it will show failure info
set response_json (echo $request_body | $curl_command )

log_ --red "## FULL RESPONSE BODY:"
echo $response_json | jq

log_ --yellow "## OUTPUT"
echo "done: $(echo $response_json | jq .done)"
echo "done_reason: $(echo $response_json | jq .done_reason)"
echo "total_duration: $(echo $response_json | jq .total_duration/1000/1000 | math -s 2) ms"
echo "load_duration: $(echo $response_json | jq .load_duration/1000/1000 | math -s 2) ms"
echo "prompt_eval_count: $(echo $response_json | jq .prompt_eval_count)"
echo "prompt_eval_duration: $(echo $response_json | jq .prompt_eval_duration/1000/1000 | math -s 2) ms"
echo "eval_count: $(echo $response_json | jq .eval_count)"
echo "eval_duration: $(echo $response_json | jq .eval_duration/1000/1000 | math -s 2) ms"
echo

log_ --blue "## COMPLETION"
echo $response_json | jq -r .response
