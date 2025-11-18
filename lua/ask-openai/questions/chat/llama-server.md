## NOTES/FIX for gptoss + llama-server messages /v1/chat/completions endpoint

```lua
--
-- * OpenAI docs show tool_call args as JSON string serialized
--   So, IIAC, llama-server would expect the same for its OpenAI compat endpoint
--   message.function.arguments => https://platform.openai.com/docs/guides/function-calling#handling-function-calls
-- OpenAI docs don't show result examples directly but does show what suggests the same thing for
--   message.content can be anything the _model can interpret_
-- * my guess is, llama server doesn't rehydrate the message.content (result)
--   like it does with message.function.arguments (I haven't confirmed, would rather spend time on my own parser)
--   - https://github.com/ggml-org/llama.cpp/blob/cb623de3f/models/templates/openai-gpt-oss-120b.jinja#L298-L299   --
--   - and __verbose.prompt shows those render as raw JSON to the prompt so they're right

--  FYI llama-server uses the gptoss jinja template w/ tojson (other models had similar part in their tool calling)
--   SO DO NOT ENCODE to JSON... else it ends up double encoded.. except I have to!
--   SEE tojson in template:
--     https://github.com/ggml-org/llama.cpp/blob/cb623de3f/models/templates/openai-gpt-oss-120b.jinja#L322

--   FYI use --verbose-prompt => logs (IIRC also final SSE) => __verbose.prompt has rendered prompt
--   ALSO harmony spec on raw JSON inputs:
--     https://cookbook.openai.com/articles/openai-harmony#receiving-tool-calls

--- FYI llama-server won't allow tool's message.content to be an object (string/array/null only)
--    self = ChatMessage:new("tool", call_result_object_not_json) -- fails
---   https://github.com/ggml-org/llama.cpp/blob/cb623de3f/tools/server/utils.hpp#L611-L614
---

-- ***! Template "FIX"
--- * I modified server template to drop |tojson and that works now (clean/raw JSON in harmony format!)
--
-- {%- elif message.role == 'tool' -%}
--     ...
--     {{- "<|start|>functions." + last_tool_call.name }}
--  * CHANGED:
--     {{- " to=assistant<|channel|>commentary<|message|>" + message.content|tojson + "<|end|>" }}
--     {{- " to=assistant<|channel|>commentary<|message|>" + message.content + "<|end|>" }}

```
