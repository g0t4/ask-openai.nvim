#!/usr/bin/env fish

set server "https://docs.langchain.com/mcp"

set call_cmd_search '{ "jsonrpc": "2.0", "id": 1, "method":"tools/call","params":{"name":"query_docs_filesystem_docs_by_lang_chain","arguments":{"command":"ls"}}}'
echo $call_cmd_search | http \
    $server \
    accept:"application/json;text/event-stream" >call_cmd_search.response

# all output
cat call_cmd_search.response | grep ^data: | string replace --regex "[^{]*" "" | jq

# just the command's STDOUT
cat call_cmd_search.response | grep -i data: | string replace --regex "[^{]*" "" | jq .result.content[0].text --raw-output
