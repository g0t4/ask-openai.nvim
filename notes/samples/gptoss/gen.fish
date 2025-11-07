#!/usr/bin/env fish

echo '{
  "messages": [ { "role": "user", "content": "test" } ],
  "max_tokens": 80,
  "stream": true
}' | curl --fail-with-body -sSL --no-buffer http://build21:8013/v1/chat/completions -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" \
    # null entries for records w/o choices[0].delta.content
    | jq --compact-output >test.stream.json

echo '{
  "messages": [ { "role": "user", "content": "test" } ],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer http://build21:8013/v1/chat/completions -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" \
    # null entries for records w/o choices[0].delta.content
    | jq --compact-output >test.full.json

# %%

# render chat template to raw prompt
echo '{
  "messages": [ { "role": "user", "content": "test" } ],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer http://build21:8013/apply-template -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" \
    # null entries for records w/o choices[0].delta.content
    | jq > test.apply-template.json

# %%

# send the rendered prompt

curl --fail-with-body -sSL --no-buffer http://build21:8013/v1/completions \
    -d @test.apply-template.json | jq
