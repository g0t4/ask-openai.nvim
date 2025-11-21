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
  "messages": [ { "role": "user", "content": "test" } ],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/apply-template" -d @- \
    | jq >test.apply-template.json

# %% * raw prompt => /v1/completions

# send the rendered prompt
curl --fail-with-body -sSL --no-buffer "$base_url/v1/completions" \
    -d @test.apply-template.json | jq >test.raw.json

# %%

#
#
# %% * NO THINK w/ pre-filled analysis channel

curl --fail-with-body -sSL --no-buffer "$base_url/v1/completions" \
    -d @./nothink/1-only-message.json | jq
