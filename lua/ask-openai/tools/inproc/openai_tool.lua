
-- **************** OpenAI INPUT MESSAGE schemas for /v1/chat/completions *****************
--
--   note: not OUTPUT schemas, these are for sending a chat completion request
--     FYI I am using longer names to namespace the schema b/c there are many ways these types are used and slight variations and I don't wanna bastardize these
--

---@class OpenAIChatCompletion_Input_AssistantMessage
---@field role string - "assistant"
---@field content string|table[] -- I am not using table[] of {type,text|refusal}
---@field tool_calls OpenAIChatCompletion_Input_AssistantMessageToolCallRequest[]
---@field name? string - NOT using (so far)
---
---@field audio any - NOT using
---@field refusal? string - NOT using
---@see https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-assistant_message

--- FYI this is not the same as above (OpenAITool) which is for defining tools
---@class OpenAIChatCompletion_Input_AssistantMessageToolCallRequest
---@field id string
---@field type string -- "function" or "custom"
---@field function OpenAIChatCompletion_Input_AssistantMessageToolCallRequestFunction
---@field custom? table -- NOT USING THIS

---@class OpenAIChatCompletion_Input_AssistantMessageToolCallRequestFunction
---@field name string
---@field arguments string -- *** in JSON format (https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-assistant_message-tool_calls-function_tool_call-function-arguments)
