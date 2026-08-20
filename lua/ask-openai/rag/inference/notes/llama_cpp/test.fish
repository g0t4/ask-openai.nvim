#!/usr/bin/env fish

# http http://ask.lan:6015/embedding input='["foo the bar"]'
curl -X POST -H "Content-Type: application/json" \
     -d '{"input": ["Hello world"]}' \
     http://ask.lan:6015/embedding
