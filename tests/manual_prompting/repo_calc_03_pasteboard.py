from show import show_completion_for

# FYI WORKS!

# FYI run as a module (not script):
#   i.e. `python -m test_calculator_context`

recent_edits_summary = """
-- The user made the following recent edits in neovim

-- calc-tests:10 added:
print("sqrt of -5 = " .. tostring(calc.sqroot(-5)))
"""
prompt_calc_user = "<|file_sep|>recent_edits\n" + recent_edits_summary

prompt_calc = "<|file_sep|>calc.lua\n<|fim_prefix|>local M = {}\n\nfunction M.add(a, b)\n    return a + b\nend\n\n<|fim_suffix|>\n\n\nreturn M<|fim_middle|>"

# TODO drop repo_name, is it ok then?
prompt = "<|repo_name|>maths\n" + prompt_calc_user + "\n" + prompt_calc

# FYI also works fine to add file_sep with calc.lua (as is expected)
request_body = {
    "prompt": prompt,
    "options": {
        "num_ctx": 8192
    },
    "raw": True,
    "num_predict": 200,
    "stream": False,
    "model": "qwen2.5-coder:7b-base-q8_0",
}

show_completion_for(request_body)
