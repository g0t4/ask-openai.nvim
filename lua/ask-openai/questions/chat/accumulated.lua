local log = require('ask-openai.logs.logger').predictions()
local ansi = require('ask-openai.prediction.ansi')

---@class AccumulatedMessage
---@field role? string
---@field index integer -- must be kept and sent back with thread
---@field content? string
---@field _verbatim_content? string -- hack for  <tool_call>... leaks (can be removed if fixed)
---@field reasoning_content? string
---@field finish_reason? string|vim.NIL -- FYI use get_finish_reason() for clean value (vim.NIL => nil)
---@field tool_call_id? string
---@field name? string
---@field tool_calls ToolCall[] -- empty if none
local AccumulatedMessage = {}

---@enum ACCUMULATED_MESSAGE_ROLES
AccumulatedMessage.ACCUMULATED_MESSAGE_ROLES = {
    -- TODO ONLY ALLOW "assistant" role? => RENAME AssistantAccumulatedMessage?
    -- TODO wait... AccumulatedMessage is the RECEIVE MODEL
    --     and ChatMessage is the SEND MODEL
    --     TODO rename ChatMessageSend / ChatMessageReceive? or smth like that?

    -- these would never come FROM the model, so don't allow them as roles!
    -- SYSTEM = "system", -- no reason for this to come back from the model so leave it off
    -- USER = "user", -- no reason for this to come back from the model so leave it off
    -- TOOL = "tool",

    ASSISTANT = "assistant",
}

--- ONLY FOR ACCUMULATING MODEL RESPONSES (over streaming SSEs)
--- NOT FOR BUILDING MESSAGES in a REQUEST (see ChatThread/ChatMessage for that)
---
---@param role ACCUMULATED_MESSAGE_ROLES|string
---@param content string|nil
---@return AccumulatedMessage
function AccumulatedMessage:new(role, content)
    self = setmetatable({}, { __index = AccumulatedMessage })
    self.role = role
    self.content = content
    self.finish_reason = nil
    self.tool_calls = {} -- empty == None (enforce invariant)
    return self
end

function AccumulatedMessage:add_tool_call_requests(call_request)
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

---@enum FINISH_REASONS
AccumulatedMessage.FINISH_REASONS = {
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
---@return FINISH_REASONS?
function AccumulatedMessage:get_finish_reason()
    if self.finish_reason == vim.NIL then
        return nil
    end
    return self.finish_reason
end

---@return boolean
function AccumulatedMessage:is_still_streaming()
    return self.finish_reason == nil or self.finish_reason == vim.NIL
end

AccumulatedMessage.LIFECYCLE = {
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

function AccumulatedMessage:get_lifecycle_step()
    -- TODO try using this to simplify consumer logic... i.e. in streaming chat window  message/tool formatters/summarizers
    if self:is_still_streaming() then
        return AccumulatedMessage.LIFECYCLE.STREAMING
    end
    local finish_reason = self:get_finish_reason()
    if finish_reason == AccumulatedMessage.FINISH_REASONS.TOOL_CALLS then
        -- IIRC tool_calls are parsed before FINISHED state... so just check all are complete (or not)
        for _, call in ipairs(self.tool_calls) do
            if not call:is_done() then
                return AccumulatedMessage.LIFECYCLE.TOOL_CALLING
            end
        end
    end
    return AccumulatedMessage.LIFECYCLE.FINISHED
end

return AccumulatedMessage
