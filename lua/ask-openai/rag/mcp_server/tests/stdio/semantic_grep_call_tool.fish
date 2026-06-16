#!/usr/bin/env fish

# Test script for calling the semantic_grep MCP tool
# Run with: fish semantic_grep_call_tool.fish

set request_init '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'

# initialized notification DOES NOT HAVE ID
set notify_initialized '{"jsonrpc":"2.0","method":"notifications/initialized"}'

# Call the semantic_grep tool with test arguments
set request_call_semantic_grep '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"semantic_grep","arguments":{"query":"where is the semantic_grep function defined?","instruct":"Find code that implements semantic search or retrieval","top_k":3,"languages":"GLOBAL"}}}'

set _python3 "$ASK_REPO/.venv/bin/python3"
begin
    echo $request_init
    sleep 1
    echo $notify_initialized
    echo $request_call_semantic_grep
    sleep 2 # wait for the tool to complete
    # just ctrl-c to stop
end \
    | env PYTHONPATH="$ASK_REPO/lua/ask-openai/rag" $_python3 -m mcp_server.__main__ --root-dir $ASK_REPO

# TODO fix logging not to write to STDOUT and then you can add `jq` back here:
# | jq
