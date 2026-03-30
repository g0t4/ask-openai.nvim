#!/usr/bin/env fish

# http http://ask.lan:8013/embedding input='["foo the bar"]'
curl -X POST -H "Content-Type: application/json" \
     -d '{"input": ["Hello world"]}' \
     http://ask.lan:8013/embedding
