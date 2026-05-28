--
-- * Tool Listing
---@class MCP_ToolInputSchemaProperty
---@field type string
---@field description? string
---@field properties? table<string, MCP_ToolInputSchemaProperty>
---@field required? string[]
---
---@class MCP_ToolInputSchema
---@field type string
---@field properties table<string, MCP_ToolInputSchemaProperty>
---@field required? string[]
---
---@class MCP_ToolOutputSchema
---@field ["$schema"]? string
---@field type string
---@field properties? table<string, table>
---@field required? string[]
---
---@class MCP_Tool
---@field icons? MCP_Icon[]
---@field name string
---@field title? string
---@field description? string
---@field inputSchema MCP_ToolInputSchema
---@field execution? MCP_ToolExecution
---@field outputSchema? MCP_ToolOutputSchema
---@field annotations? MCP_ToolAnnotations
---@field _meta? MCP_Meta
---@field call fun(id: integer|string, tool_name: string, args: table, callback: ToolCallDoneCallback, on_progress: ToolCallOnProgress) -- my function to invoke the tool, not part of MCP specification
---
---@class MCPToolsListResult
---@field result? MCP_ListToolsResult
---@field error? MCP_JSONRPCError
---
---@class MCP_ListToolsRequest
---@field jsonrpc string   -- "2.0"
---@field method string    -- "tools/list"
---@field id MCP_RequestId
---@field params? MCP_PaginatedRequestParams
---
---@class MCP_ListToolsResult
---@field _meta? MCP_Meta
---@field nextCursor? string
---@field tools MCP_Tool[]
---@field [string] unknown

-- * Tool Execution
---@class MCP_CallToolSuccessResponse
---@field result MCP_CallToolResult

---@class MCP_CallToolRequest
---@field jsonrpc "2.0"
---@field id MCP_RequestId
---@field method "tools/call"
---@field params MCP_CallToolRequestParams
---
---@class MCP_CallToolRequestParams
---@field task? MCP_TaskMetadata
---@field _meta? MCP_MetaWithProgressToken
---@field name string
---@field arguments? table<string, any>
---
---@class MCP_CallToolResult: table<string, any>
---@field _meta? table<string, unknown>
---@field content MCP_ContentBlock[]
---@field structuredContent? table<string, unknown>
---@field isError? boolean

-- MCP schemas: https://modelcontextprotocol.io/specification/2025-11-25/schema
---@class MCP_JSONRPCError
---@field code: integer
---@field message string
---@field data? any

---@alias MCP_ProgressToken string | number
---@alias MCP_RequestId string | number

--- @class MCP_JSONRPCErrorResponse
--- @field jsonrpc "2.0"
--- @field id? MCP_RequestId
--- @field error MCP_JSONRPCError

--- @class MCP_JSONRPCResultResponse
--- @field jsonrpc "2.0"
--- @field id MCP_RequestId
--- @field result MCP_Result

--- @class MCP_JSONRPCNotification
--- @field jsonrpc "2.0"
--- @field method string
--- @field params? table<string, any>

--- @class MCP_JSONRPCRequest
--- @field jsonrpc "2.0"
--- @field method string
--- @field params? table<string, any>
--- @field id MCP_RequestId

---@alias MCP_JSONRPCResponse MCP_JSONRPCResultResponse | MCP_JSONRPCErrorResponse
---@alias MCP_JSONRPCMessage MCP_JSONRPCRequest | MCP_JSONRPCNotification | MCP_JSONRPCResponse

---@alias MCP_LoggingLevel "debug" | "info" | "notice" | "warning" | "error" | "critical" | "alert" | "emergency"

---@class MCP_SetLevelRequest
---@field jsonrpc "2.0"
---@field id MCP_RequestId
---@field method string   -- "logging/setLevel"
---@field params MCP_SetLevelRequestParams

---@class MCP_SetLevelRequestParams
---@field _meta? MCP_MetaWithProgressToken
---@field level MCP_LoggingLevel

---@class MCP_Result : table<string, any>
---@field _meta? MCP_Meta

---@alias MCP_ContentBlock MCP_TextContent | MCP_ImageContent | MCP_AudioContent | MCP_ResourceLink | MCP_EmbeddedResource

---@class MCP_TextContent
---@field type string
---@field text string
---@field name? string -- FYI I added this, i.e. to hold "STDOUT" or "EXIT_CODE" etc
---@field annotations? MCP_Annotations
---@field _meta? MCP_Meta

---@class MCP_ServerCapabilities
---@field experimental? table<string, any>
---@field logging? any
---@field completions? any
---@field prompts? {listChanged?: boolean}
---@field resources? {subscribe?: boolean, listChanged?: boolean}
---@field tools? {listChanged?: boolean}
---@field tasks? {list?: any, cancel?: any, requests?: {tools?: {call?: any}}}

---@class MCP_ProgressNotification: MCP_JSONRPCNotification
---@field jsonrpc "2.0"
---@field method "notifications/progress"
---@field params MCP_ProgressNotificationParams

---@class MCP_ProgressNotificationParams
---@field _meta? MCP_Meta
---@field progressToken MCP_ProgressToken
---@field progress number
---@field total? number
---@field message? string

---@class MCP_LoggingMessageNotificationParams
---@field _meta? MCP_Meta
---@field level MCP_LoggingLevel
---@field logger? string
---@field data any

---@class MCP_LoggingMessageNotification
---@field jsonrpc "2.0"
---@field method "notifications/message"
---@field params MCP_LoggingMessageNotificationParams

---@class MCP_CreateTaskResult: table<string,any>
---@field _meta? MCP_Meta
---@field task MCP_Task

---@class MCP_RelatedTaskMetadata
---@field taskId string

---@class MCP_Task
---@field task_id string
---@field status MCP_TaskStatus
---@field status_message? string
---@field created_at string
---@field last_updated_at string
---@field ttl number|nil
---@field poll_interval? number

---@class MCP_TaskMetadata
---@field ttl? number

---@class MCP_TaskStatusNotification
---@field jsonrpc "2.0"
---@field method "notifications/tasks/status"
---@field params MCP_TaskStatusNotificationParams

---@alias MCP_TaskStatus "working" | "input_required" | "completed" | "failed" | "cancelled"

---@class MCP_TaskStatusNotificationParams : MCP_NotificationParams, MCP_Task

---@class MCP_GetTaskPayloadRequest
---@field jsonrpc "2.0"
---@field id MCP_RequestId
---@field method "tasks/result"
---@field params {taskId:string}

---@class MCP_GetTaskPayloadResult
---@field _meta? MCP_Meta
---@field [string] any

---@class MCP_ListTasksRequest
---@field jsonrpc "2.0"
---@field id MCP_RequestId
---@field params? MCP_PaginatedRequestParams
---@field method string   -- "tasks/list"

---@class MCP_ListTasksResult: table<string, any>
---@field _meta? MCP_Meta
---@field nextCursor? string
---@field tasks MCP_Task[]

---@class MCP_CancelTaskRequest
---@field jsonrpc "2.0"
---@field id MCP_RequestId
---@field method "tasks/cancel"
---@field params {taskId: string}

---@class MCP_CancelTaskResult: MCP_Result & MCP_Task

---@class MCP_GetTaskRequest
---@field jsonrpc "2.0"
---@field id MCP_RequestId
---@field method "tasks/get"
---@field params {taskId: string}

---@class MCP_GetTaskResult: MCP_Result & MCP_Task

---FYI this type is not documented in MCP schema page, just referenced as a type
---@class MCP_NotificationParams

---@class MCP_InitializedNotification
---@field jsonrpc "2.0"
---@field method "notifications/initialized"
---@field params? MCP_NotificationParams

---@class MCP_CancelledNotificationParams
---@field _meta? MCP_Meta
---@field requestId? MCP_RequestId
---@field reason? string

---@class MCP_CancelledNotification
---@field jsonrpc "2.0"
---@field method "notifications/cancelled"
---@field params MCP_CancelledNotificationParams

---@class MCP_ClientCapabilities
---@field experimental? table<string, table>
---@field roots? {listChanged?: boolean}
---@field sampling? {context?: table, tools?: table}
---@field elicitation? {form?: table, url?: table}
---@field tasks? {
---    list?: table,
---    cancel?: table,
---    requests?: {
---        sampling?: {createMessage?: table},
---        elicitation?: {create?: table},
---    },
---}

---@class MCP_MetaWithProgressToken : table<string, any>
---@field MCP_progressToken?: string|integer

---@class MCP_Meta : table<string, any>

---@class MCP_InitializeRequestParams
---@field _meta? MCP_MetaWithProgressToken
---@field protocolVersion string
---@field capabilities MCP_ClientCapabilities;
---@field clientInfo MCP_Implementation

---@class MCP_InitializeRequest
---@field jsonrpc "2.0"
---@field id MCP_RequestId
---@field method "initialize"
---@field params MCP_InitializeRequestParams

---@class MCP_InitializeResult: table<string, any>
---@field _meta? MCP_Meta
---@field protocolVersion string
---@field capabilities MCP_ServerCapabilities
---@field serverInfo MCP_Implementation
---@field instructions? string
