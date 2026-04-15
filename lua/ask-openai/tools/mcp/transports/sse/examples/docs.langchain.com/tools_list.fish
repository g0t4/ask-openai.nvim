#!/usr/bin/env fish

set initalize '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'

set list_tools '{ "jsonrpc": "2.0", "id": 1, "method": "tools/list" }'

echo $initalize | http "https://docs.langchain.com/mcp"


