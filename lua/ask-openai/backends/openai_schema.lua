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




