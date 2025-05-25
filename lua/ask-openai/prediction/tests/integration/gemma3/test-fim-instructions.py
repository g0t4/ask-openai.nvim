from show import show_completion_for

prompt = """
Complete the missing code between the given sections. Only provide the code that fills the gap.

**Prefix:**
def calculate_average(numbers):
    if not numbers:
        return 0
    total = sum(numbers)

**Suffix:**
    return average

**Missing Code:**
"""

request_body = {
    "prompt": prompt,
    "options": {
        "num_ctx": 8192
    },
    "raw": True,
    "num_predict": 200,
    "stream": False,
    "model": "gemma3:12b",
}

show_completion_for(request_body)
