local log = require('ask-openai.logs.logger').predictions()
local ansi = require('ask-openai.prediction.ansi')
local shared = require('ask-openai.questions.chat.messages.shared')

---@class RxAccumulatedMessage
---@field role? string
---@field index integer -- TODO! this appears to be Rx side only (it is not in OpenAI docs for chat completions endpoint, on any message type)... I believe I just need choice.index if there are multiple response rx_messages for one request ... but I wouldn't need it on the rx_message... just the dict that looksup rx mesage by choice.index ... IOTW I think I can remove tracking index ... ALSO choice.index is always 0 b/c it is PER response!
---@field content? string
---@field _verbatim_content? string -- hack for  <tool_call>... leaks (can be removed if fixed)
---@field reasoning_content? string
---@field finish_reason? string|vim.NIL -- FYI use get_finish_reason() for clean value (vim.NIL => nil)
---@field tool_call_id? string
---@field name? string
---@field tool_calls ToolCall[] -- empty if none
local RxAccumulatedMessage = {}

---@enum RX_MESSAGE_ROLES
local RX_MESSAGE_ROLES = {
    -- these would never come FROM the model, so don't allow them as roles!
    -- SYSTEM = "system", -- no reason for this to come back from the model so leave it off
    -- USER = "user", -- no reason for this to come back from the model so leave it off
    -- TOOL = "tool",

    -- pretty much just assistant role...
    --   that said, easy enough to force a model to generate any role
    --   by hard coding it as the last part of the (raw) prompt
    ASSISTANT = "assistant",
}

--- ONLY FOR ACCUMULATING MODEL RESPONSES (over streaming SSEs)
--- NOT FOR BUILDING MESSAGES in a REQUEST (see ChatThread/TxChatMessage for that)
---
---@param role RX_MESSAGE_ROLES|string - Theoretically ONLY assistant role... but no reason to limit a model that generates a diff role(s)
---@param content string|nil
---@return RxAccumulatedMessage
function RxAccumulatedMessage:new(role, content)
    self = setmetatable({}, { __index = RxAccumulatedMessage })
    self.role = role
    self.content = content
    self.finish_reason = nil
    self.tool_calls = {} -- empty == None (enforce invariant)

    if role ~= RX_MESSAGE_ROLES.ASSISTANT then
        -- NOT really an error, I just want it to stand out
        -- mostly I am interested in when this happens so I can build that into my mental model of this RxAccumulatedMessage type
        log:error("[WARN] unexpected role (not a problem, just heads up so you can think about it): " .. tostring(role))
        -- TODO remove this logging when you think you have enough history collected
    end

    return self
end

---Returns the finish reason, cleanup when not set (i.e. nil instead of vim.NIL)
--- not set when still streaming
---@return FINISH_REASON?
function RxAccumulatedMessage:get_finish_reason()
    if self.finish_reason == vim.NIL then
        return nil
    end
    return self.finish_reason
end

---@return boolean
function RxAccumulatedMessage:is_still_streaming()
    return self.finish_reason == nil or self.finish_reason == vim.NIL
end

---@enum RX_LIFECYCLE
RxAccumulatedMessage.RX_LIFECYCLE = {
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

---@return RX_LIFECYCLE
function RxAccumulatedMessage:get_lifecycle_step()
    -- TODO try using this to simplify consumer logic... i.e. in streaming chat window  message/tool formatters/summarizers
    if self:is_still_streaming() then
        return RxAccumulatedMessage.RX_LIFECYCLE.STREAMING
    end
    local finish_reason = self:get_finish_reason()
    if finish_reason == shared.FINISH_REASON.TOOL_CALLS then
        -- IIRC tool_calls are parsed before FINISHED state... so just check all are complete (or not)
        for _, call in ipairs(self.tool_calls) do
            if not call:is_done() then
                return RxAccumulatedMessage.RX_LIFECYCLE.TOOL_CALLING
            end
        end
    end
    return RxAccumulatedMessage.RX_LIFECYCLE.FINISHED
end

return RxAccumulatedMessage
