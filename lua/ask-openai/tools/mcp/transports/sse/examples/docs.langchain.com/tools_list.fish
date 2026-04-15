#!/usr/bin/env fish

set initalize '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
# got this error: {"jsonrpc":"2.0","error":{"code":-32000,"message":"Not Acceptable: Client must accept both application/json and text/event-stream"},"id":null}

set list_tools '{ "jsonrpc": "2.0", "id": 1, "method": "tools/list" }'

echo $initalize | http \
    "https://docs.langchain.com/mcp" \
    accept:"application/json;text/event-stream" > initialize.response
# event: message
# data: {
#     "id": 1,
#     "jsonrpc": "2.0",
#     "result": {
#         "capabilities": {
#   ...



