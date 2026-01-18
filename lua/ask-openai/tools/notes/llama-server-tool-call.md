## llama-server qwen3coder30b sample of tool call


The following is a capture, sans some of the input prompt and also ids that I stripped to keep it more concise (where you find ... that means I stripped smth)

````json

// * INPUT:
{"messages":[{"content":"Your name is Qwenny...","role":"system"},{"content":"what is the current directory?:","role":"user"}],"temperature":0.3,"model":"qwen3coder30b","tools":[{"type":"function","function":{"name":"run_command","parameters":{"type":"object","properties":{"workdir":{"description":"Optional, current working directory","type":"string"},"command":{"description":"Command with args","type":"string"},"stdin":{"description":"Optional, text to pipe into the command's STDIN. For example, pass a python script to python3. Or, pass text for a new file to the cat command to create it!","type":"string"}},"required":["command"]},"description":"Run a command on this darwin machine"}}],"stream":true}



// * SSE RESPONSEs
{"choices":[
        {"finish_reason":null,"index":0,"delta":{"role":"assistant","content":null}}
    ],
    "created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
{"choices":[
        {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"id":"v2dh...","type":"function","function":{"name":"run_command","arguments":""}}
    ]}}],
    "created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
{"choices": [
        {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\""}}
    ]}}],
    "created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
{"choices":[
        {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"command"}}
    ]}}],
    "created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
{"choices":[
        {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\":"}}
    ]}}],
    "created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
{"choices":[
        {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\""}}
    ]}}],
    "created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
{"choices":[
        {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"pwd"}}
    ]}}],
    "created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}
{"choices":[
        {"finish_reason":null,"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}
    ]}}],
    "created":1758541572,"id":"...","model":"qwen3coder30b","system_fingerprint":"...","object":"chat.completion.chunk"}

// last SSE:
{
  "choices": [
    { "finish_reason": "tool_calls", "index": 0, "delta": {} }
  ],
  "created": 1758541572,
  "id": "...",
  "model": "qwen3coder30b",
  "system_fingerprint": "...",
  "object": "chat.completion.chunk",
  "timings": {
    "cache_n": 0,
    "prompt_n": 463,
    "prompt_ms": 62.703,
    "prompt_per_token_ms": 0.13542764578833694,
    "prompt_per_second": 7384.016713713857,
    "predicted_n": 20,
    "predicted_ms": 102.018,
    "predicted_per_token_ms": 5.1009,
    "predicted_per_second": 196.04383540159577
  },
  "__verbose": {
    "index": 0,
    "content": "",
    "tokens": [],
    "id_slot": 0,
    "stop": true,
    "model": "qwen3coder30b",
    "tokens_predicted": 20,
    "tokens_evaluated": 463,
    "generation_settings": {
      "n_predict": -1,
      "seed": 4294967295,
      "temperature": 0.30000001192092896,
      "dynatemp_range": 0.0,
      "dynatemp_exponent": 1.0,
      "top_k": 40,
      "top_p": 0.949999988079071,
      "min_p": 0.05000000074505806,
      "top_n_sigma": -1.0,
      "xtc_probability": 0.0,
      "xtc_threshold": 0.10000000149011612,
      "typical_p": 1.0,
      "repeat_last_n": 64,
      "repeat_penalty": 1.0,
      "presence_penalty": 0.0,
      "frequency_penalty": 0.0,
      "dry_multiplier": 0.0,
      "dry_base": 1.75,
      "dry_allowed_length": 2,
      "dry_penalty_last_n": 65536,
      "dry_sequence_breakers": [
        "\n",
        ":",
        "\"",
        "*"
      ],
      "mirostat": 0,
      "mirostat_tau": 5.0,
      "mirostat_eta": 0.10000000149011612,
      "stop": [],
      "max_tokens": -1,
      "n_keep": 0,
      "n_discard": 0,
      "ignore_eos": false,
      "stream": true,
      "logit_bias": [],
      "n_probs": 0,
      "min_keep": 0,
      "grammar": "any-tool-call ::= ( run-command-call ) space\nchar ::= [^\"\\\\\\x7F\\x00-\\x1F] | [\\\\] ([\"\\\\bfnrt] | \"u\" [0-9a-fA-F]{4})\nroot ::= tool-call\nrun-command-args ::= \"{\" space run-command-args-command-kv ( \",\" space ( run-command-args-workdir-kv run-command-args-workdir-rest | run-command-args-stdin-kv ) )? \"}\" space\nrun-command-args-command-kv ::= \"\\\"command\\\"\" space \":\" space string\nrun-command-args-stdin-kv ::= \"\\\"stdin\\\"\" space \":\" space string\nrun-command-args-workdir-kv ::= \"\\\"workdir\\\"\" space \":\" space string\nrun-command-args-workdir-rest ::= ( \",\" space run-command-args-stdin-kv )?\nrun-command-call ::= \"{\" space run-command-call-name-kv \",\" space run-command-call-arguments-kv \"}\" space\nrun-command-call-arguments ::= \"{\" space run-command-call-arguments-command-kv ( \",\" space ( run-command-call-arguments-workdir-kv run-command-call-arguments-workdir-rest | run-command-call-arguments-stdin-kv ) )? \"}\" space\nrun-command-call-arguments-command-kv ::= \"\\\"command\\\"\" space \":\" space string\nrun-command-call-arguments-kv ::= \"\\\"arguments\\\"\" space \":\" space run-command-call-arguments\nrun-command-call-arguments-stdin-kv ::= \"\\\"stdin\\\"\" space \":\" space string\nrun-command-call-arguments-workdir-kv ::= \"\\\"workdir\\\"\" space \":\" space string\nrun-command-call-arguments-workdir-rest ::= ( \",\" space run-command-call-arguments-stdin-kv )?\nrun-command-call-name ::= \"\\\"run_command\\\"\" space\nrun-command-call-name-kv ::= \"\\\"name\\\"\" space \":\" space run-command-call-name\nrun-command-function-tag ::= \"<function\" ( \"=run_command\" | \" name=\\\"run_command\\\"\" ) \">\" space run-command-args \"</function>\" space\nspace ::= | \" \" | \"\\n\"{1,2} [ \\t]{0,20}\nstring ::= \"\\\"\" char* \"\\\"\" space\ntool-call ::= run-command-function-tag | wrappable-tool-call | ( \"```\\n\" | \"```json\\n\" | \"```xml\\n\" ) space wrappable-tool-call space \"```\" space \nwrappable-tool-call ::= ( any-tool-call | \"<tool_call>\" space any-tool-call \"</tool_call>\" | \"<function_call>\" space any-tool-call \"</function_call>\" | \"<response>\"  space any-tool-call \"</response>\" | \"<tools>\"     space any-tool-call \"</tools>\" | \"<json>\"      space any-tool-call \"</json>\" | \"<xml>\"      space any-tool-call \"</xml>\" | \"<JSON>\"      space any-tool-call \"</JSON>\" ) space\n",
      "grammar_lazy": true,
      "grammar_triggers": [
        {
          "type": 1,
          "value": "<function=run_command>"
        },
        {
          "type": 2,
          "value": "<function\\s+name\\s*=\\s*\"run_command\""
        },
        {
          "type": 3,
          "value": "(?:<think>[\\s\\S]*?</think>\\s*)?\\s*((?:<tool_call>|<function|(?:```(?:json|xml)?\n\\s*)?(?:<function_call>|<tools>|<xml><json>|<response>)?\\s*\\{\\s*\"name\"\\s*:\\s*\"(?:run_command)\"))[\\s\\S]*"
        }
      ],
      "preserved_tokens": [
        73594,
        151657,
        151658,
        151667,
        151668
      ],
      "chat_format": "Hermes 2 Pro",
      "reasoning_format": "auto",
      "reasoning_in_content": false,
      "thinking_forced_open": false,
      "samplers": [
        "penalties",
        "dry",
        "top_n_sigma",
        "top_k",
        "typ_p",
        "top_p",
        "min_p",
        "xtc",
        "temperature"
      ],
      "speculative.n_max": 16,
      "speculative.n_min": 0,
      "speculative.p_min": 0.75,
      "timings_per_token": false,
      "post_sampling_probs": false,
      "lora": []
    },
    "prompt": "<|im_start|>system\nYour name is Qwenny...\n\nYou have access to the following functions:\n\n<tools>\n<function>\n<name>run_command</name>\n<description>Run a command on this darwin machine</description>\n<parameters>\n<parameter>\n<name>workdir</name>\n<type>string</type>\n<description>Optional, current working directory</description>\n</parameter>\n<parameter>\n<name>command</name>\n<type>string</type>\n<description>Command with args</description>\n</parameter>\n<parameter>\n<name>stdin</name>\n<type>string</type>\n<description>Optional, text to pipe into the command's STDIN. For example, pass a python script to python3. Or, pass text for a new file to the cat command to create it!</description>\n</parameter>\n<required>['command']</required>\n</parameters>\n</function>\n</tools>\n\nIf you choose to call a function ONLY reply in the following format with NO suffix:\n\n<tool_call>\n<function=example_function_name>\n<parameter=example_parameter_1>\nvalue_1\n</parameter>\n<parameter=example_parameter_2>\nThis is the value for the second parameter\nthat can span\nmultiple lines\n</parameter>\n</function>\n</tool_call>\n\n<IMPORTANT>\nReminder:\n- Function calls MUST follow the specified format: an inner <function=...></function> block must be nested within <tool_call></tool_call> XML tags\n- Required parameters MUST be specified\n- You may provide optional reasoning for your function call in natural language BEFORE the function call, but NOT after\n- If there is no function call available, answer the question like normal with your current knowledge and do not tell the user about function calls\n</IMPORTANT><|im_end|>\n<|im_start|>user\nwhat is the current directory?:<|im_end|>\n<|im_start|>assistant\n",
    "has_new_line": true,
    "truncated": false,
    "stop_type": "eos",
    "stopping_word": "",
    "tokens_cached": 482,
    "timings": {
      "cache_n": 0,
      "prompt_n": 463,
      "prompt_ms": 62.703,
      "prompt_per_token_ms": 0.13542764578833694,
      "prompt_per_second": 7384.016713713857,
      "predicted_n": 20,
      "predicted_ms": 102.018,
      "predicted_per_token_ms": 5.1009,
      "predicted_per_second": 196.04383540159577
    }
  }
}

````
