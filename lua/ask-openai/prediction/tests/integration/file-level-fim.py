import json
import requests

raw_print = print
from rich import print

def show_completion_for(body):
    print("[blue]## PROMPT")
    raw_print(body["prompt"])

    response = requests.post(
        "http://ollama:11434/api/generate",
        headers={"Content-Type": "application/json"},
        data=json.dumps(body),
    )

    print("[yellow]## OUTPUT")
    result = response.json()
    print(f"done: {result.get('done')}")
    print(f"done_reason: {result.get('done_reason')}")
    print(f"total_duration: {float(result.get('total_duration', 0)) / 1000000:.2f} ms")
    print(f"load_duration: {float(result.get('load_duration', 0)) / 1000000:.2f} ms")
    print(f"prompt_eval_count: {result.get('prompt_eval_count')}")
    print(f"prompt_eval_duration: {float(result.get('prompt_eval_duration', 0)) / 1000000:.2f} ms")
    print(f"eval_count: {result.get('eval_count')}")
    print(f"eval_duration: {float(result.get('eval_duration', 0)) / 1000000:.2f} ms")
    print()

    print("[blue]## COMPLETION")
    completion = result["response"]
    raw_print(completion)

request_body = {
    "prompt": "<|fim_prefix|>local M = {}\n\nfunction M.add(a, b)\n    return a + b\nend\n\n<|fim_suffix|>\n\n\nreturn M<|fim_middle|>",
    "options": {
        "num_ctx": 8192
    },
    "raw": True,
    "num_predict": 200,
    "stream": False,
    "model": "qwen2.5-coder:7b-base-q8_0",
}

show_completion_for(request_body)
