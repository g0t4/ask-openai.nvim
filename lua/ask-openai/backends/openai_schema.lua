--
-- * CHAT STREAMING SCHEMA (OUTPUT, not INPUT)
-- FYI it is ok to extend this with llama.cpp server differences (just mark them)
--  use this to type the incoming parsed SSEs
-- FYI! this was originally setup for curl_streaming's on_streaming_delta_update_message_history parsed SSE inputs

---@alias OpenAIChatCompletionParsedSSE OpenAIChatCompletionChunk

--- docs: https://platform.openai.com/docs/api-reference/chat-streaming/streaming
---@class OpenAIChatCompletionChunk
---@field choices OpenAIChoice[]
---@field created integer
---@field id string
---@field model string
---@field object string -- "chat.completion.chunk"
---@field service_tier string
---@field system_fingerprint string -- deprecated
---@field usage OpenAIUsage|nil

--- docs: https://platform.openai.com/docs/api-reference/chat-streaming/streaming#chat_streaming-streaming-usage
---@class OpenAIUsage
---@field completion_tokens integer
---@field prompt_tokens integer
---@field total_tokens integer
---@field completion_tokens_details OpenAIUsageCompletionTokenDetails[]
---@field prompt_tokens_details OpenAIUsagePromptTokenDetails[]

--- docs: https://platform.openai.com/docs/api-reference/chat-streaming/streaming#chat_streaming-streaming-usage-completion_tokens_details
---@class OpenAIUsageCompletionTokenDetails
---@field accepted_prediction_tokens integer
---@field audio_tokens integer
---@field reasoning_tokens integer
---@field rejected_prediction_tokens integer

--- docs: https://platform.openai.com/docs/api-reference/chat-streaming/streaming#chat_streaming-streaming-usage-prompt_tokens_details
---@class OpenAIUsagePromptTokenDetails
---@field audio_tokens integer
---@field cached_tokens integer

--- docs: https://platform.openai.com/docs/api-reference/chat-streaming/streaming#chat_streaming-streaming-choices
---@class OpenAIChoice
---@field delta OpenAIChoiceDelta
---@field finish_reason string|nil
---@field index integer
---@field logprobs OpenAIChoiceLogProbs|nil

--- docs: https://platform.openai.com/docs/api-reference/chat-streaming/streaming#chat_streaming-streaming-choices-logprobs
---@class OpenAIChoiceLogProbs -- PRN
---@field content []|nil
---@field refusal []|nil

--- docs: https://platform.openai.com/docs/api-reference/chat-streaming/streaming#chat_streaming-streaming-choices-delta
---@class OpenAIChoiceDelta
---@field content string
---@field function_call -- DEPRECATED, use tool_calls
---@field refusal string
---@field role string
---@field tool_calls OpenAIChoiceDeltaToolCall[]|nil
---@field reasoning_content string|nil -- llama.cpp only?

--- docs: https://platform.openai.com/docs/api-reference/chat-streaming/streaming#chat_streaming-streaming-choices-delta-tool_calls
---@class OpenAIChoiceDeltaToolCall
---@field index integer
---@field function OpenAIChoiceDeltaToolCallFunction|nil
---@field id string
---@field type string -- currently "function" only

---@class OpenAIChoiceDeltaToolCallFunction
---@field name string
---@field arguments string -- typically JSON (from model) though should be validated

-- **************** OpenAI INPUT MESSAGE schemas for /v1/chat/completions *****************
--
--   note: not OUTPUT schemas, these are for sending a chat completion request
--     FYI I am using longer names to namespace the schema b/c there are many ways these types are used and slight variations and I don't wanna bastardize these
--

--- * Message Types (by Role)

---@class OpenAIChatCompletion_TxChatMessage
---@field role string
---@field content OpenAIChatCompletion_MessageContent - btw role="user" has a few extra item times in table[]
---@field name? string - NOT using (so far)

---@class OpenAIChatCompletion_System_TxChatMessage : OpenAIChatCompletion_TxChatMessage
---@field role string - "system"

---@class OpenAIChatCompletion_Developer_TxChatMessage : OpenAIChatCompletion_TxChatMessage
---@field role string - "developer"

---@class OpenAIChatCompletion_User_TxChatMessage : OpenAIChatCompletion_TxChatMessage
---@field role string - "user"

--- For returning tool call results to the model (assistant)
---  FTR no `name` field
---@class OpenAIChatCompletion_ToolResult_TxChatMessage : OpenAIChatCompletion_TxChatMessage
---@field role string - "tool"
---@field tool_call_id string

--- I'm ONLY USING string
--- I am not using table[] of {type,text|refusal} - all message roles have these two (and then user role has a few more item types)
---@see https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-assistant_message-content
---
---@alias OpenAIChatCompletion_MessageContent string|table[]

-- * Assistant Message Type (has extras like tool calls)

---@class OpenAIChatCompletion_Assistant_TxChatMessage : OpenAIChatCompletion_TxChatMessage
---@field role string - "assistant"
---@field tool_calls OpenAIChatCompletion_Assistant_TxChatMessage_ToolCallRequest[]
---@field reasoning_content string? - NOT in the OPENAI SPEC (llama-server uses this)
---
---@field audio any - NOT using
---@field refusal? string - NOT using
---@see https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-assistant_message

---@class OpenAIChatCompletion_Assistant_TxChatMessage_ToolCallRequest
---@field id string
---@field type string -- "function" or "custom"
---@field function OpenAIChatCompletion_Assistant_TxChatMessage_ToolCallRequestFunction
---@field custom? table -- NOT USING THIS
-- FYI this is GOOD EXAMPLE of why I want split type definitions (INPUT vs OUTPUT):
--   there is no `ToolCall.index` input like there is on the SSEs in the output!

---@class OpenAIChatCompletion_Assistant_TxChatMessage_ToolCallRequestFunction
---@field name string
---@field arguments string -- *** in JSON format (https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-assistant_message-tool_calls-function_tool_call-function-arguments)
-- TODO FINISH THESE WITH TxChatMessage refactoring








-- **************** OpenAI Tool Definition schemas for /v1/chat/completions *****************
--    these are for defining "available tools" .. not for tool calls
--

-- * tool schema: https://platform.openai.com/docs/api-reference/chat/create?api-mode=chat#chat_create-tools
--   note this is not the same as the deprecated "function calling" FYL
--   two types:
--     Function tool
--     Custom tool
--       - b/c functions aren't custom! lol
--  FYI guide here: https://platform.openai.com/docs/guides/function-calling
--  - BUT... FFS the openai client pypi package (appears) to not follow the schema for defining a tool?!
--    - flattens Tool.type => onto function.type

---@class OpenAITool
---@field type string -- "function" or "custom"
---@field function FunctionTool -- required if using function tool
---@field custom? CustomTool -- required if using custom tool

---@class CustomTool - not using this

---@class FunctionTool
---@field name string - required [a-zA-Z\d_-] "maxlen"==64 (wtf? max length?)
---@field description? string
---@field parameters? FunctionParameters - nil == no params
---@field strict? boolean - "default"==false whether (or not?) the model strictly adheres to the function schema in a tool call request?! lol you're kidding, right?

---@class FunctionParameters
---@field type string -- "object" for multiple params -- TODO is there a different type for a tool w/ a single parameter?
---@field properties table<string,FunctionParameter> -- key == parameter_name
---@field required string[] -- required parameters (by name)

---@class FunctionParameter
---@field type string - i.e. "string", "number", ? others? (required? or is string the default?)
---@field description? string

-- PRN move the MCP to OpenAI logic here?
