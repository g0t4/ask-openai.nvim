

## JSON-RPC 2.0

- Terminology take from JSON-RPC 2.0 spec: https://www.jsonrpc.org/specification
  - `Client` - origin of `Request` objects, handler of `Response` objects
  - `Server` - origin of `Response` objects, handler of `Request` objects
  - `JSON` - the data format
    - `Primitive` types - `String`, `Boolean`, `Number`, `Null`
      - `Boolean` - `True` or `False`
    - `Structured` types - `Object`, `Array`
  - `Request` - Client initiated RPC call, with these fields:
    - `jsonrpc` String ALWAYS set to `2.0`
    - `id` String or Number
    - `method` String
    - `params` Structured value
      - `Array` - pass parameters by-position
      - `Object` - pass parameters by-name
  - `Response` - summarizes result of RPC call, with these fields:
    - `jsonrpc` String ALWAYS set to `2.0`
    - `id` - must match the corresonding `Request` `id`
    - `result` - required on Success
    - `error` - Object, required on Failure
      - `code` Integer - server defined codes
        - `-32768` to `-32000` are reserved for pre-defined erorrs
          - `-32700` Parse error
          - `-32600` Invalid Request
          - `-32601` Method not found
          - `-32602` Invalid params
          - `-32603` Internal error
          - `-32000` to `-32099` Server error (reserved for implementation‑defined server‑errors)
      - `message` String - short description
      - `data` Any type -
  - `Notification` - a `Request` object without an `id` value
    - `Server` must not confirm a `Notification`

## Model Context Protocol over Streamable HTTP

- Specification details: https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
  - Versioned (URL includes version, i.e. 2025-11-25 is the most recent version)
  - Server endpoint must listen on ONE endpoint path, commonly `/mcp`
    - Accepts both `POST` and `GET` methods
    - Optionally support Server-Sent Events (SSE) to stream multiple messages
- Each `Client` `Request` is sent as a _NEW_ HTTP `POST` request.
  - AFAICT request batching is not supported.
  - `Server` must send `Response`
- `Client`:
  - HTTP POST to send _ONE_ message (JSON-RPC object)
    - Header with `accept: application/json;text/event-stream`
      - Client must support both types based on Server's `Content-Type` header
    - Body has single message
- `Server`:
  - `Content-Type: text/event-stream` to start an SSE stream
  - `Content-Type: application/json` to return ONE JSON object
  - Reponds with `202 Accepted` (no body) or an HTTP error status code on failure
- For `SSE` streams:
  - immediately send SSE event with event ID and empty data field
    - client reconnects with `Last-Event-ID` header with the provided event ID from the server
  - if server closes connection, client can "poll" the SSE stream to reconnect
    - server should send `retry` field before closing connection
  - Server can send SSE Notifications before the Response
    - Server terminates SSE stream after Response sent
  - Disconnect does not mean the client is canceling its Request
    - To cancel, Client must send `CancelledNotification`
  - Stream can be made to be Resumable
- Client can use HTTP GET to open an SSE stream, listing `Accept: text/event-stream` as the only acceptable content type
  - Server responds with matching `Content-Type`... or HTTP 405 (Method Not Allowed)
  - This is how a Client resumes an SSE stream with an outstanding Response (not yet sent)
    - HTTP GET + `Last-Event-ID` header with corresponding event ID
- Session management - optional
  - Server may attach `MCP-Session-Id` header (unique + cryptographically secure - visible ASCII chars)
    - ** Client must include the `MCP-Session-Id ` header in subseuqent HTTP requests
  - IIUC sessions make use of `InitializeRequest` from the client and a corresponding Response from the server.
  - Server can terminate session at any time, responding with `404` to the session ID after termination
    - Client can send a new InitializeRequest w/o session ID to start a new session
  - Clients send `HTTP DELETE` to terminate the session
- Protocol Version Header
  - Client MUST include `MCP-Protocol-Version: <protocol-version>` using protocol version negotiated during initialization
- Legacy `HTTP with SSE` docs: https://modelcontextprotocol.io/specification/2024-11-05/basic/transports#http-with-sse
  - predates `Streamable HTTP` transport (described above)
  - Backwards compat: https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#backwards-compatibility

## Model Context Protocol over STDIO

- Recommended that all clients support STDIO.
- Docs: https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#stdio
- Client runs Server in a sub-process:
  - STDOUT for sending messages (Requests/Notifications)
      - DO NOT USE STDOUT for anything else, only JSON-RPC messages
  - STDIN for receiving messages (Responses/Notifications)
  - messages are _NEWLINE_ delimited
    - DO NOT embed newlines within a message!
  - STDERR may be used informally for logging
- Client terminates Server when done

