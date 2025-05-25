from show import show_completion_for

request_body = {
    "prompt": "<pr>Title: fix race condition\ng0t4: race caused crashes<pr_status>opened<repo_name>",

    "options": {
        "num_ctx": 8192
    },
    "raw": True,
    "num_predict": 200,
    "stream": False,
    "model": "starcoder2:7b-q8_0",
}

show_completion_for(request_body)
