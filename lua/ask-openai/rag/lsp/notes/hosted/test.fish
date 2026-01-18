#!/usr/bin/env fish

# http http://ollama:8013/embedding input='["foo the bar"]'
curl -X POST -H "Content-Type: application/json" \
     -d '{"input": ["Hello world"]}' \
     http://ollama:8013/embedding
