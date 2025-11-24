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
