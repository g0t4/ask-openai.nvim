#!/usr/bin/env fish

set request_init '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'

# initialized notification DOES NOT HAVE ID
set notify_initialized '{"jsonrpc":"2.0","method":"notifications/initialized"}'

set request_tools_list '{ "jsonrpc": "2.0", "id": 2, "method":"tools/list","params":{}}'
# set request_call_delegate '{ "jsonrpc": "2.0", "id": 2, "method":"tools/call","params":{"name":"delegate","arguments":{"description": "what is the news"}}}'

set _python3 "$ASK_REPO/.venv/bin/python3"
begin
    echo $request_init
    sleep 1
    echo $notify_initialized
    echo $request_tools_list
    sleep 1 # wait enough time for subagent to sufficiently have a chance to run! it can take a while depending on what it sets out to do!
    # just ctrl-c to stop
    # w/o sleep this shell script dies and kills `uv run` with it... silently appears to fail.. when in reality the subagent was cranking away!
end \
    | env PYTHONPATH="$ASK_REPO/lua/ask-openai/rag" $_python3 -m mcp_server.__main__ --root-dir $ASK_REPO
# TODO fix logging not to write to STDOUT and then you can add `jq` back here:
# | jq

# uv run \
#     --directory ~/repos/github/g0t4/mcp-servers/src/agents \
# -m subagents \
