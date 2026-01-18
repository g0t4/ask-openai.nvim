#
# * additional files as context!
#    https://huggingface.co/JetBrains/Mellum-4b-base#fill-in-the-middle-with-additional-files-as-context-generation
#
prompt = """<filename>utils.py
def multiply(x, y):
    return x * y
<filename>config.py
DEBUG = True
MAX_VALUE = 100
<filename>example.py
<fim_suffix>

# Test the function
result = calculate_sum(5, 10)
print(result)<fim_prefix>def calculate_sum(a, b):
<fim_middle>"""

import requests
import json

raw_print = print
from rich import print

def vllm_completion_for(body):
    print("[blue]## PROMPT")
    raw_print(body["prompt"])

    response = requests.post(
        "http://ollama:8000/v1/completions",
        headers={"Content-Type": "application/json"},
        data=json.dumps(body),
    )

    print("[yellow]## OUTPUT")
    result = response.json()
    print("result", result)
    # print(f"done: {result.get('done')}")
    # print(f"done_reason: {result.get('done_reason')}")
    # print(f"total_duration: {float(result.get('total_duration', 0)) / 1000000:.2f} ms")
    # print(f"load_duration: {float(result.get('load_duration', 0)) / 1000000:.2f} ms")
    # print(f"prompt_eval_count: {result.get('prompt_eval_count')}")
    # print(f"prompt_eval_duration: {float(result.get('prompt_eval_duration', 0)) / 1000000:.2f} ms")
    # print(f"eval_count: {result.get('eval_count')}")
    # print(f"eval_duration: {float(result.get('eval_duration', 0)) / 1000000:.2f} ms")
    print()

    print("[blue]## COMPLETION")
    completion = result["choices"][0]["text"]
    raw_print(completion)

# FYI also works fine to add file_sep with calc.lua (as is expected)
request_body = {
    "prompt": prompt,
    "options": {
        "num_ctx": 8192
    },
    # "raw": True,
    "num_predict": 300,
    # "stream": False,
    # "model": "qwen2.5-coder:7b-base-q8_0",
}

vllm_completion_for(request_body)
