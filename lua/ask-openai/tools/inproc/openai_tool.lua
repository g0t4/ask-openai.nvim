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
