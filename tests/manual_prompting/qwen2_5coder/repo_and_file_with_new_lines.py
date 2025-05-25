from show import show_completion_for

# FYI run as a module (not script):
#   i.e. `python -m file_level_fim`
#   `python -m file_name_without_ext` b/c then I can keep shared show lib in dir above and nest diff "modules" in dirs like "worked"

# FYI also works fine to add file_sep with calc.lua (as is expected)
request_body = {
    "prompt": "<|repo_name|>maths\n<|file_sep|>calc.lua\n<|fim_prefix|>local M = {}\n\nfunction M.add(a, b)\n    return a + b\nend\n\n<|fim_suffix|>\n\n\nreturn M<|fim_middle|>",
    "options": {
        "num_ctx": 8192
    },
    "raw": True,
    "num_predict": 200,
    "stream": False,
    "model": "qwen2.5-coder:7b-base-q8_0",
}

show_completion_for(request_body)
