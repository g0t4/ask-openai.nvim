## reproducing MCP server issues

* SEE executable scripts:
  https://github.com/g0t4/mcp-server-commands/blob/master/tests/manual/stdio/tool_call_success_big.fish

## backend support for tools:

YES:
- /v1/chat/completions (openai compat)
   - validated ollama, vllm support tools with this endpoint too
   - important to check, b/c some "openai compatible" backends may not support all openai compat params
- /api/chat (ollama)

NO:
- /v1/completions (openai - not in API spec)
- /api/generate (ollama)


## NOTES:

 MCP docs:
   spec: https://modelcontextprotocol.io/specification/2025-03-26
   message formats: https://modelcontextprotocol.io/specification/2025-03-26/basic#messages
     requests: https://modelcontextprotocol.io/specification/2025-03-26/basic#requests
     responses: https://modelcontextprotocol.io/specification/2025-03-26/basic#responses
   schema: https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2025-03-26/schema.json
