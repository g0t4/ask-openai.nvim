local log = require('devtools.logs.logger').universal()
local ansi = require('devtools.ansi')
local shared = require('ask-openai.agents.messages.shared')

---@class RxAccumulatedMessage
---@field role? string
---@field index integer -- TODO! this appears to be Rx side only (it is not in OpenAI docs for chat completions endpoint, on any message type)... I believe I just need choice.index if there are multiple response rx_messages for one request ... but I wouldn't need it on the rx_message... just the dict that looksup rx mesage by choice.index ... IOTW I think I can remove tracking index ... ALSO choice.index is always 0 b/c it is PER response!
---@field content? string
---@field _verbatim_content? string -- hack for  <tool_call>... leaks (can be removed if fixed)
---@field reasoning_content? string
---@field finish_reason? string
---@field tool_call_id? string
---@field name? string
---@field tool_calls ToolCall[] -- empty if none
---@field last_sse? LlamaServerSSEBase
---@field timings? LlamaServerTimings
local RxAccumulatedMessage = {}

local ASSISTANT = "assistant"

-- TODO! 2026-11-27 get rid of this entire piece of shit class as soon as curl backend handles AccumulatedCompletion
--    TODO! then it will be obvious as day the difference between AccumulatedCompletion and what you send back!
---
--- ONLY FOR ACCUMULATING MODEL RESPONSES (over streaming SSEs)
--- NOT FOR BUILDING MESSAGES in a REQUEST (see AgentTrace/TxChatMessage for that)
---
---@param role string - Theoretically ONLY assistant role... but no reason to limit a model that generates a diff role(s)
---@param content string|nil
---@return RxAccumulatedMessage
function RxAccumulatedMessage:new(role, content)
    self = setmetatable({}, { __index = RxAccumulatedMessage })
    -- Default to assistant when role is missing (some backends omit `role` in
    -- the first SSE delta, e.g. when reasoning is off or content-only chunks)
    self.role = role or ASSISTANT -- the fact that I hard code this here if not set is evidence of shitty code for accumulating
    self.content = content
    self.finish_reason = nil
    self.tool_calls = {} -- empty == None (enforce invariant)

    if self.role ~= ASSISTANT then
        -- FYI can remove this logging, mostly out of curiosity
        log:warn("[WARN] unexpected role (not a problem, just heads up so you can think about it): " .. tostring(self.role))
    end

    return self
end

---@return boolean
function RxAccumulatedMessage:is_still_streaming()
    -- TODO... issue with timing... it usually ususally comes AFTER finish_reason
    -- TODO use the new AccumulatedCompletion type to determine when streaming is done and not this
    --    FYI this is why I don't get timings in the lua chat viewer for non-llama-server backends!!
    return self.finish_reason == nil
end

---@return boolean
function RxAccumulatedMessage:is_done_streaming()
    return not self:is_still_streaming()
end

return RxAccumulatedMessage
