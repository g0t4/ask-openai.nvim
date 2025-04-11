

 NOTES

 MCP docs:
   spec: https://modelcontextprotocol.io/specification/2025-03-26
   message formats: https://modelcontextprotocol.io/specification/2025-03-26/basic#messages
     requests: https://modelcontextprotocol.io/specification/2025-03-26/basic#requests
     responses: https://modelcontextprotocol.io/specification/2025-03-26/basic#responses
   schema: https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2025-03-26/schema.json


more examples from Claude's log files!
- /Users/wesdemos/Library/Logs/Claude/mcp.log


 *** working examples (manual testing)

   tools/list
     { "jsonrpc": "2.0", "id": 4, "method": "tools/list", "params": {} }
     { "jsonrpc": "2.0", "id": 1, "method": "tools/list" }

     won't work if jsonrpc is missing, or params is serialized to an array []
     don't send params if empty, set it nil before serializing

 FYI practice sending messages:
   node /Users/wesdemos/repos/github/g0t4/mcp-server-commands/build/index.js --verbose
      then paste manual messages into prompt and hit return (new line) to submit
      entire message must be on one line

   npm run inspector
      use gui to design messages and then can see the payload and copy/paste it

