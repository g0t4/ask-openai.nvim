Notes w.r.t. tool use in /v1/chat/completions endpoints

## 2.5-Coder vllm tools not working

This is a common issue it seems:
*https://github.com/QwenLM/Qwen2.5-Coder/issues/180#issuecomment-2523247811*

Notes:
- Qwen2 style function calling might work w/ vllm + coder
- Coder's github does not mention tool use on top level page whereas the non-Coder variant has several references to it
- Qwen manual - shows how to use tools with Qwen2.5 only: https://qwen.readthedocs.io/en/latest/framework/function_call.html#id8
- also possible I need a diff tool call parser for vllm?
- PRN can I get ollama to show me the unparsed initial model response?  just to see what it looks like?

   vllm serve Qwen/Qwen2.5-Coder-7B-Instruct --enable-auto-tool-choice --tool-call-parser hermes     # not ever giving tool calls in vllm only
   vllm serve Qwen/Qwen2.5-7B-Instruct --enable-auto-tool-choice --tool-call-parser hermes           # giving tool calls

## ollama doesn't support stream+tools for /v1/chat/completions
NOT YET => maybe soon => https://github.com/ollama/ollama/issues/8887#issuecomment-2640721896
can set stream w/ tools but model responds with one/few chunks after full response is ready
   basically the same as disabling streaming

FTR... if tools are requested, it's usually fast (one or two small chunks).. so I don't care if that is not streaming
  I get to show the tool_calls to the user and then they'll know (that is very stream like)
issue is... I want any non-tool use (i.e. explanations) to be streaming
WORST CASE - I might need to use a raw /api/chat and format the request and parse response myself.... shouldn't need to though (vllm I bet has streaming tools)

