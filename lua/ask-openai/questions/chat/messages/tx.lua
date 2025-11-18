local log = require('ask-openai.logs.logger').predictions()
local ansi = require('ask-openai.prediction.ansi')

---@class TxChatMessage
---@field role? string
---@field index integer -- must be kept and sent back with thread
---@field content? string
---@field _verbatim_content? string -- hack for  <tool_call>... leaks (can be removed if fixed)
---@field reasoning_content? string
---@field finish_reason? string|vim.NIL -- TODO I do not think I would be sending vim.NIL right? that's only in streaming when the response is not yet complete?
---@field tool_call_id? string
---@field name? string
---@field tool_calls ToolCall[] -- empty if none
local TxChatMessage = {}

---@enum TX_MESSAGE_ROLES
local TX_MESSAGE_ROLES = {
    USER = "user",
    ASSISTANT = "assistant",
    TOOL = "tool", -- FYI this is for TOOL RESULTS
    SYSTEM = "system",
}

-- TODO! I want end to end testing to verify scenarios that go into the model (the actual prompt) based on TxChatMessage inputs
--  TxChatMessage inputs => .__verbose.prompt output
--  will require --verbose-prompt arg to llama-server
--  VERIFY |tojson fix for tool results, AND tool call args
--  VERIFY other fixes identified by unsloth:
--     https://unsloth.ai/blog/gpt-oss
--     icdiff https://huggingface.co/openai/gpt-oss-120b/raw/main/chat_template.jinja https://huggingface.co/unsloth/gpt-oss-120b/raw/main/chat_template.jinja

---@param role TX_MESSAGE_ROLES
---@param content string
---@return TxChatMessage
function TxChatMessage:new(role, content)
    self = setmetatable({}, { __index = TxChatMessage })
    self.role = role
    self.content = content
    self.finish_reason = nil
    self.tool_calls = {} -- empty == None (enforce invariant)
    return self
end

-- IDEA:
-- function TxChatMessage:from_accumulated(RxAccumulatedMessage accumulated)
--     -- TODO see ask.lua curl_exited_successfully (move that logic here? or move this idea to RxAccumulatedMessage?)
-- end

---@param tool_call ToolCall
---@return TxChatMessage
function TxChatMessage:tool_result(tool_call)
    -- FYI see NOTES.md for "fix" => removed `|tojson` from jinja template for message.content
    local content = vim.json.encode(tool_call.call_output.result)
    self = TxChatMessage:new(TX_MESSAGE_ROLES.TOOL, content)

    self.tool_call_id = tool_call.id
    self.name = tool_call["function"].name
    return self
end

---@return TxChatMessage
function TxChatMessage:system(content)
    return TxChatMessage:new(TX_MESSAGE_ROLES.SYSTEM, content)
end

---@return TxChatMessage
function TxChatMessage:user(content)
    return TxChatMessage:new(TX_MESSAGE_ROLES.USER, content)
end

--- differentiate TxChatMessage usage by making explicit this provides context to another user request
---@return TxChatMessage
function TxChatMessage:user_context(content)
    -- FYI it would be fine to remove this after my RxAccumulatedMessage refactor
    return TxChatMessage:user(content)
end

---@return TxChatMessage
function TxChatMessage:add_tool_call_requests(call_request)
    -- ONLY clone fields on the original call request from the model
    local new_call = {
        id = call_request.id,
        index = call_request.index,
        type = call_request.type,
        ["function"] = {
            name = call_request["function"].name,
            arguments = call_request["function"].arguments,
        }
    }
    table.insert(self.tool_calls, new_call)
end

return TxChatMessage
