#!/usr/bin/env fish

set call_search '{ "jsonrpc": "2.0", "id": 1, "method":"tools/call","params":{"name":"search_docs_by_lang_chain","arguments":{"query":"tool calls"}}}'

set server "https://docs.langchain.com/mcp"

echo $call_search | http \
    $server \
    accept:"application/json;text/event-stream" > call_search.response

cat call_search.response | grep ^data: | string replace --regex "[^{]*" "" | jq
