from show import show_completion_for

request_body = {
    "prompt": "<fim_prefix>local M = {}\n\nfunction M.add(a, b)\n    return a + b\nend\n\n<fim_suffix>\n\n\nreturn M<fim_middle>",
    "options": {
        "num_ctx": 8192
    },
    "raw": True,
    "num_predict": 200,
    "stream": False,
    "model": "huggingface.co/JetBrains/Mellum-4b-base-gguf:latest",
}

show_completion_for(request_body)
