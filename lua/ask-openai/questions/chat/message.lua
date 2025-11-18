local log = require('ask-openai.logs.logger').predictions()
local ansi = require('ask-openai.prediction.ansi')

---@class ChatMessage
---@field role? string
---@field index integer -- must be kept and sent back with thread
---@field content? string
---@field _verbatim_content? string -- hack for  <tool_call>... leaks (can be removed if fixed)
---@field reasoning_content? string
---@field finish_reason? string|vim.NIL -- FYI use get_finish_reason() for clean value (vim.NIL => nil)
---@field tool_call_id? string
---@field name? string
---@field tool_calls ToolCall[] -- empty if none
local ChatMessage = {}

---@enum TX_MESSAGE_ROLES
local TX_MESSAGE_ROLES = {
    USER = "user",
    ASSISTANT = "assistant",
    TOOL = "tool", -- FYI this is for TOOL RESULTS
    SYSTEM = "system",
}

-- TODO! I want end to end testing to verify scenarios that go into the model (the actual prompt) based on ChatMessage inputs
--  ChatMessage inputs => .__verbose.prompt output
--  will require --verbose-prompt arg to llama-server
--  VERIFY |tojson fix for tool results, AND tool call args
--  VERIFY other fixes identified by unsloth:
--     https://unsloth.ai/blog/gpt-oss
--     icdiff https://huggingface.co/openai/gpt-oss-120b/raw/main/chat_template.jinja https://huggingface.co/unsloth/gpt-oss-120b/raw/main/chat_template.jinja

---@param role TX_MESSAGE_ROLES
---@param content string
---@return ChatMessage
function ChatMessage:new(role, content)
    self = setmetatable({}, { __index = ChatMessage })
    self.role = role
    self.content = content
    self.finish_reason = nil
    self.tool_calls = {} -- empty == None (enforce invariant)
    return self
end

-- IDEA:
-- function ChatMessage:from_accumulated(AccumulatedMessage accumulated)
--     -- TODO see ask.lua curl_exited_successfully (move that logic here? or move this idea to AccumulatedMessage?)
-- end

---@param tool_call ToolCall
---@return ChatMessage
function ChatMessage:new_tool_response(tool_call)
    -- FYI see NOTES.md for "fix" => removed `|tojson` from jinja template for message.content
    local content = vim.json.encode(tool_call.call_output.result)
    self = ChatMessage:new(TX_MESSAGE_ROLES.TOOL, content)

    self.tool_call_id = tool_call.id
    self.name = tool_call["function"].name
    return self
end

---@return ChatMessage
function ChatMessage:system(content)
    return ChatMessage:new(TX_MESSAGE_ROLES.SYSTEM, content)
end

---@return ChatMessage
function ChatMessage:user(content)
    return ChatMessage:new(TX_MESSAGE_ROLES.USER, content)
end

--- differentiate ChatMessage usage by making explicit this provides context to another user request
---@return ChatMessage
function ChatMessage:user_context(content)
    -- FYI it would be fine to remove this after my AccumulatedMessage refactor
    return ChatMessage:user(content)
end

---@return ChatMessage
function ChatMessage:add_tool_call_requests(call_request)
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

---@enum TX_FINISH_REASONS
ChatMessage.TX_FINISH_REASONS = {
    LENGTH = "length",
    STOP = "stop",
    TOOL_CALLS = "tool_calls",
    -- observed finish_reason values: "tool_calls", "stop", "length", null (not string, a literal null JSON value)
    -- vim.NIL (still streaming) => b/c of JSON value of null (not string, but literal null in the JSON)

    -- FYI find finish_reason observed values:
    --   grep --no-filename -o '"finish_reason":[^,}]*' **/* 2>/dev/null | sort | uniq
    -- "finish_reason":"length"
    -- "finish_reason":"stop"
    -- "finish_reason":"tool_calls"
    -- "finish_reason":null
}

---Returns the finish reason, cleanup when not set (i.e. nil instead of vim.NIL)
---@return TX_FINISH_REASONS?
function ChatMessage:get_finish_reason()
    if self.finish_reason == vim.NIL then
        return nil
    end
    return self.finish_reason
end

---@return boolean
function ChatMessage:is_still_streaming()
    return self.finish_reason == nil or self.finish_reason == vim.NIL
end

---@enum TX_LIFECYCLE
ChatMessage.LIFECYCLE = {
    -- FYI I merged two concepts: message from model + managing requested tool_call object(s)
    -- streaming -> rx finish_reason=stop/length -> finished
    -- streaming -> rx finish_reason=tool_calls -> pending_tool_call -> calling -> rx results -> finished (tool call done)

    STREAMING = "streaming", -- server is sending message (streaming SSEs)
    FINISHED = "finished", -- server is done sending the message

    -- * tool call related
    -- PENDING_TOOL_CALL = "pending_tool_call", -- next the client will call the tool (add this only IF NEEDED)
    TOOL_CALLING = "tool_calling", -- client is calling the tool, waiting for it to complete
    TOOLS_DONE = "tool_called", -- tool finished (next message will send results to server for a new "TURN" in chat history)
}

---@return TX_LIFECYCLE
function ChatMessage:get_lifecycle_step()
    -- TODO try using this to simplify consumer logic... i.e. in streaming chat window  message/tool formatters/summarizers
    if self:is_still_streaming() then
        return ChatMessage.LIFECYCLE.STREAMING
    end
    local finish_reason = self:get_finish_reason()
    if finish_reason == ChatMessage.TX_FINISH_REASONS.TOOL_CALLS then
        -- IIRC tool_calls are parsed before FINISHED state... so just check all are complete (or not)
        for _, call in ipairs(self.tool_calls) do
            if not call:is_done() then
                return ChatMessage.LIFECYCLE.TOOL_CALLING
            end
        end
    end
    return ChatMessage.LIFECYCLE.FINISHED
end

return ChatMessage
