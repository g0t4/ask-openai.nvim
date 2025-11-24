#!/usr/bin/env fish


# ***! TLDR: template+tools dictate chat content/reasoning settings
#   *        + raw endpoint == no template => different settings!

# FOR qwen3-8b.service (or similar params)

set base_url 'http://build21:8013'

# %% * /props vs __verbose.generation_settings - how to find chat format (content, reasoning, etc) settings

# 1. Look at config for the loaded model
curl build21.lan:8013/props | jq 'del(.chat_template)'
# FYI RAW PROMPT => RAW OUTPUT (AFAICT, these settings apply to raw prompts for the model):
#  "chat_format": "Content-only",
#  "reasoning_format": "none",
#  "reasoning_in_content": false,
#  "thinking_forced_open": false,
#
# FYI /v1/chat/completions => __verbose.generation_settings has different values b/c it uses a template
#  and templates on the input side correlate to parsers on the output side
#  TEMPLATE IN => think "TEMPLATE OUT"
#    Aside - I am curious to know if I can mix and match:
#      RAW IN => TEMPLATE OUT  (IIAC I can adjust chat_format, reasoning_format, etc to do this)
#      TEMPLATE IN => RAW OUT
echo '{
  "messages": [ { "role": "user", "content": "test" } ],
  "max_tokens": 200,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/v1/chat/completions" -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" | jq
# ! /v1/chat/completions params:
# "chat_format": "Hermes 2 Pro",
# "reasoning_format": "deepseek",
# "reasoning_in_content": false,
# "thinking_forced_open": false,

# 3. chat_format = "Content-only" maps to:
#     case COMMON_CHAT_FORMAT_CONTENT_ONLY: return "Content-only";
#         https://github.com/ggml-org/llama.cpp/blob/7d77f0732/common/chat.cpp#L627
#     which uses:
#         static void common_chat_parse_content_only(common_chat_msg_parser & builder) {
#             builder.try_parse_reasoning("<think>", "</think>"); # * so even with content only you can parse think tags if reasoning_format is not NONE (IIUC)
#             builder.add_content(builder.consume_rest());
#         }
#
# 3. chat_format = "Hermes 2 Pro" maps to:
#     case COMMON_CHAT_FORMAT_HERMES_2_PRO: return "Hermes 2 Pro";
# static void common_chat_parse_hermes_2_pro(common_chat_msg_parser & builder) {
#     builder.try_parse_reasoning("<think>", "</think>");
#     if (!builder.syntax().parse_tool_calls) {
#         builder.add_content(builder.consume_rest());
#         return;
#     }
#
#     static const common_regex open_regex(
#         "(?:"
#             "(```(?:xml|json)?\\n\\s*)?" // match 1 (block_start)
#             "("                          // match 2 (open_tag)
#                 "<tool_call>"
#                 "|<function_call>"
#                 "|<tool>"
#                 "|<tools>"
#                 "|<response>"
#                 "|<json>"
#                 "|<xml>"
#                 "|<JSON>"
#             ")?"
#             "(\\s*\\{\\s*\"name\")" // match 3 (named tool call)
#         ")"
#         "|<function=([^>]+)>"            // match 4 (function name)
#         "|<function name=\"([^\"]+)\">"  // match 5 (function name again)
#     );
#
# 3b... !!! settings are determined by template + tools
#     # makes sense as these formats are largely for parsing generated tool calls
#
#     static common_chat_params common_chat_templates_apply_jinja(
#     const struct common_chat_templates        * tmpls,
#     const struct common_chat_templates_inputs & inputs)
#
#       const auto & src = tmpl.source();
#
#     # not far down you'll find (so it looks at the template and if it finds <tool_call> then it assumes Hermes 2/3 Pro (etc)
#
#       // Hermes 2/3 Pro, Qwen 2.5 Instruct (w/ tools)
#       if (src.find("<tool_call>") != std::string::npos && params.json_schema.is_null()) {
#           return common_chat_params_init_hermes_2_pro(tmpl, params);
#       }
#
#       // GPT-OSS
#       if (src.find("<|channel|>") != std::string::npos) {
#           return common_chat_params_init_gpt_oss(tmpl, params);
#       }
#
#     # then toward end:
#
#       // Generic fallback
#       return common_chat_params_init_generic(tmpl, params);
#
# 3c. common_chat_syntax struct (related settings for content/reasoning parsing):
#
#     # https://github.com/ggml-org/llama.cpp/blob/7d77f0732/common/chat.h#L159-L166
#
#         struct common_chat_syntax {
#             common_chat_format       format                = COMMON_CHAT_FORMAT_CONTENT_ONLY;
#             common_reasoning_format  reasoning_format      = COMMON_REASONING_FORMAT_NONE;
#             // Whether reasoning_content should be inlined in the content (e.g. for reasoning_format=deepseek in stream mode)
#             bool                     reasoning_in_content  = false;
#             bool                     thinking_forced_open  = false;
#             bool                     parse_tool_calls      = true;
#         };
#


# %% * /v1/chat/completions

# ! set /nothink in content (user message) to stop thinking
echo '{
  "messages": [ { "role": "user", "content": "test" } ],
  "max_tokens": 200,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/v1/chat/completions" -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" \
    jq >test.full.json

# %% * /apply-template

# render chat template to raw prompt
echo '{
  "messages": [ { "role": "user", "content": "what is the date?" } ],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/apply-template" -d @- \
    | jq >test.apply-template.json
# {
#   "prompt": "<|im_start|>user\nwhat is the date?<|im_end|>\n<|im_start|>assistant\n"
# }

cat test.apply-template.json | jq .prompt -r # show just the prompt

# %% * raw prompt => /completions (NOT OpenAI compat)
# send the rendered prompt

mkdir -p completions

# FYI /completions == /completion
curl --fail-with-body -sSL --no-buffer "$base_url/completions" \
    -d @test.apply-template.json | jq > completions/raw.json
# results in <think>...</think> response


# * add /nothink for qwen3 to not think
echo '{
  "messages": [ { "role": "user", "content": "what is the date? /nothink" } ],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/apply-template" -d @- \
    | jq >test.apply-template-nothink.json

curl --fail-with-body -sSL --no-buffer "$base_url/completions" \
    -d @test.apply-template-nothink.json | jq > completions/nothink.raw.json
# "content": "<think>\n\n</think>\n\nAs of my knowledge..."

# %% * raw prompt => /v1/completions (OpenAI compat)

mkdir -p v1_completions_oai

curl --fail-with-body -sSL --no-buffer "$base_url/v1/completions" \
    -d @test.apply-template.json | jq >v1_completions_oai/raw.json

# TODO do I need to set raw=true for /v1/completions or does it detect raw prompt, or?
#
# BTW can override reasoning_format and chat_format (does nothing for /v1/completions nor /completions... reasoning_content must only be for /chat/completions endpoint?)
# FYI for chat_format, get the # 11 from enum: https://github.com/ggml-org/llama.cpp/blob/7d77f0732/common/chat.h#L112
#   it won't accept the string value you get in __verbose.generation_settings.chat_format output
cat test.apply-template.json | jq 'add(.reasoning_format="deepseek")' | jq 'add(.chat_format=11)' \
    | curl --fail-with-body -sSL --no-buffer "$base_url/v1/completions" -d @-  \
    | string replace --regex  "^data: " "" \
        | jq > v1_completions_oai/raw.json
# TODO! find out if I can mix and match template/raw IN <=> parsed/raw OUT
#     where parsed means chat_format/reasoning_format extracting reasoning from content
#       and extracting tool calls from content

