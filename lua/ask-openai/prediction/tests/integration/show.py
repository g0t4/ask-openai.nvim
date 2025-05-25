import requests
import json

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
