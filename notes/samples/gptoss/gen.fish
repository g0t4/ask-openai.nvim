#!/usr/bin/env fish

set base_url 'http://build21:8013'

# %% * /v1/chat/completions

echo '{
  "messages": [ { "role": "user", "content": "test" } ],
  "max_tokens": 80,
  "stream": true
}' | curl --fail-with-body -sSL --no-buffer "$base_url/v1/chat/completions" -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" \
    # null entries for records w/o choices[0].delta.content
    | jq --compact-output >test.stream.json

echo '{
  "messages": [ { "role": "user", "content": "test" } ],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/v1/chat/completions" -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" \
    # null entries for records w/o choices[0].delta.content
    | jq --compact-output >test.full.json

# %% * /apply-template

# render chat template to raw prompt
echo '{
  "messages": [ { "role": "user", "content": "what is the date?" } ],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/apply-template" -d @- \
    | jq >test.apply-template.json

cat test.apply-template.json | jq .prompt -r # show just the prompt

# %% * raw prompt => /completions (NOT OpenAI compat)
# send the rendered prompt

mkdir -p completions

# FYI /completions == /completion
curl --fail-with-body -sSL --no-buffer "$base_url/completions" \
    -d @test.apply-template.json | jq > completions/raw.json

# modify
cat test.apply-template.json | jq 'add(.stream=true)'

# streaming => flat SSEs => .content,.tokens,.stop (.index,.tokens_predicted,.tokens_evaluated)
cat test.apply-template.json | jq 'add(.stream=true)' | \
    curl --fail-with-body -sSL --no-buffer "$base_url/completions" -d @- \
    | string replace --regex  "^data: " "" | jq >completions/raw.stream.json
# {
#   "index": 0,
#   "content": "5",
#   "tokens": [
#     20
#   ],
#   "stop": false,
#   "id_slot": -1,
#   "tokens_predicted": 71,
#   "tokens_evaluated": 72
# }
#
# FYI 200002 is last token => <|return|> ... though, llama-server does not show the token <|return|> (maybe an option to do so?)


# -d @-     ==> means STDIN => request body

# %% * raw prompt => /v1/completions (OpenAI compat)

mkdir -p v1_completions_oai

curl --fail-with-body -sSL --no-buffer "$base_url/v1/completions" \
    -d @test.apply-template.json | jq >v1_completions_oai/raw.json

# streaming => .choices[0].text
cat test.apply-template.json | jq 'add(.stream=true)' | \
    curl --fail-with-body -sSL --no-buffer "$base_url/v1/completions" -d @- \
    | string replace --regex  "^data: " "" | string replace --regex "\[DONE\]" "" \
    | jq >v1_completions_oai/raw.stream.json
# bulk of response is in:
#
#   "choices": [
#     {
#       "text": "",
#       "index": 0,
#       "logprobs": null,
#       "finish_reason": null
#     }
#   ],
#
# SUPER COOL! .__verbose shows underlying /completions like format
#    IIAC that is b/c /v1/completions simply transforms /completions format?
#   "__verbose": {
#     "index": 0,
#     "content": "<|channel|>",
#     "tokens": [
#       200005
#     ],
#     "stop": false,
#     "id_slot": -1,
#     "tokens_predicted": 1,
#     "tokens_evaluated": 72
#   }
#

#
# %% * NO THINK w/ pre-filled analysis channel

curl --fail-with-body -sSL --no-buffer "$base_url/completions" \
    -d @./nothink/1-only-message.json | jq
# "index": 0,
# "content": "<|message|>Got it! If you have any questions or need assistance, just let me know. 😊",
# "tokens": [],
# "id_slot": 3,
# "stop": true,
# "model": "gpt-3.5-turbo",
# "tokens_predicted": 20,
# "tokens_evaluated": 99,

# "truncated": false,
# "stop_type": "eos",
# "stopping_word": "",


# %% * /props - verify config + chat template
#  especially to verify ENV VARS / CLI ARGS applied as expected

curl build21.lan:8013/props | jq .

# drop chat_template (big item) so it is easier to see the rest:
curl build21.lan:8013/props | jq 'del(.chat_template)'

# only chat_template:
curl build21.lan:8013/props | jq .chat_template



# %% ** TEST prefill_assistant_message
#  s/b able to modify last assistant message instead of it being generated?
#  looks like I can provide literal prompt text too?
#
#  see chat args parsing logic here:
#    https://github.com/ggml-org/llama.cpp/blob/7d77f0732/tools/server/utils.hpp#L727-L748
#  for /v1/chat/completions endpoint (obviously)
#    https://github.com/ggml-org/llama.cpp/blob/7d77f0732/tools/server/utils.hpp#L727-L763
#    TODO test w/ verbose-prompt on
#
#  IIUC it only is enabled via CLI arg?
#    https://github.com/ggml-org/llama.cpp/blob/7d77f0732/common/arg.cpp#L2534
#

# * prefill (default on)
echo '{
  "messages": [
     { "role": "user", "content": "test" }
],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/v1/chat/completions" -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" \
    # null entries for records w/o choices[0].delta.content
    | jq > prefill1.json

# normally a message ends with smth like this (this is gptoss):
#    <|start|>assistant
#
# (b/c of add_generation_prompt in templates)


# ***! prefill + assistant is last message w/ content string or array, injects values (i.e. to control thinking)
#  this allow you to prefill part of the assistant message! (i.e. disable thinking)

echo '{
  "messages": [
     { "role": "user", "content": "test" },
     { "role": "assistant", "content": "INJECTED RIGHT INTO PROMPT!!" }
],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/v1/chat/completions" -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" \
    # null entries for records w/o choices[0].delta.content
    | jq > prefill2.json
# BTW what I INJECTED here breaks the typical flow and in this case the model responds with multiple messages, almost ignoring what I INJECTED
#  here is its response:
#     "content": " \n\nIt looks ...<|end|><|start|>assistant<|channel|>analysis<|message|>The user just wrote \"test\". Likely they are testing. Should respond politely. Probably just echo or respond. As ChatGPT, respond \"Hello! How can I assist you today?\"<|end|><|start|>assistant<|channel|>final<|message|>Hello! How can I help you today?",


# * use it to set part or all of thinking:
# in gptoss, add_generation_prompt injects this on end (and before any prefill):
# <|start|>assistant
# which allows gptoss to respond with analysis channel first, optionally tool calls on commentary channel, finally final channel w/ final message for the turn
#   btw I am not appending <|message|> after final b/c IIRC llama-cpp uses <|message|> as part of its partial processing for this prefilled message when then on the output side doesn't have a header
#
#   FTR can also pass array of content items instead of just one string
#
# here's the code where I found this:
#   https://github.com/ggml-org/llama.cpp/blob/7d77f0732/tools/server/utils.hpp#L753-L762
#
echo '{
  "messages": [
     { "role": "user", "content": "test" },
     { "role": "assistant", "content": "<|channel|>analysis<|message|>no thoughts for you<|end|><|start|>assistant<|channel|>final" }
],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/v1/chat/completions" -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" \
    # null entries for records w/o choices[0].delta.content
    | jq > prefill3.json
# BINGO! in this case I just get
#     "content": "<|message|>Test successful! 🎉 Let me know if there's anything you'd like to explore or discuss.",
