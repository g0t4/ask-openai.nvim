

import json
import requests
from rich import print

request_body = {
    "prompt": "</think>local M = {}\n\nfunction M.add(a, b)\n    return a + b\nend\n\n\nreturn M\n",
    "options": {
        "num_ctx": 8192
    },
    "raw": True,
    "num_predict": 200,
    "stream": False,
    "model": "qwen2.5-coder:7b-base-q8_0"
}

print("[blue]## PROMPT[/blue]")
print(json.dumps(request_body["prompt"], indent=2))

curl_command = "curl -fsSL --no-buffer -H \"Content-Type: application/json\" http://ollama:11434/api/generate -d @-"

response = requests.post(
    "http://ollama:11434/api/generate",
    headers={"Content-Type": "application/json"},
    data=json.dumps(request_body)
)

print("[yellow]## OUTPUT[/yellow]")
print(f"done: {response.json().get('done')}")
print(f"done_reason: {response.json().get('done_reason')}")
print(f"total_duration: {float(response.json().get('total_duration', 0)) / 1000000:.2f} ms")
print(f"load_duration: {float(response.json().get('load_duration', 0)) / 1000000:.2f} ms")
print(f"prompt_eval_count: {response.json().get('prompt_eval_count')}")
print(f"prompt_eval_duration: {float(response.json().get('prompt_eval_duration', 0)) / 1000000:.2f} ms")
print(f"eval_count: {response.json().get('eval_count')}")
print(f"eval_duration: {float(response.json().get('eval_duration', 0)) / 1000000:.2f} ms")
print()

print("[blue]## COMPLETION[/blue]")echo $response_json | jq -r .response
