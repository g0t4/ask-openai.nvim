--- FYI MUST MIRROR OpeanAI format b/c this will get sent back
---   i.e. that means function is a nested object
---@class ToolCall : OpenAIChoiceDeltaToolCall
---
---  my additions:
---@field response_message table|nil -- TODO type this? response message to send call results back to the model that will, also attached to agent_trace (history)
---@field call_output? ToolCallOutput -- tool call outputs (specific to a given tool type, some have standard structure, i.e. MCP)
---@field progress_messages string[] -- progress messages received during tool execution
---@field start_time_ms integer -- timestamp (ms) when tool execution began (set by frontend before calling tool)
local ToolCall = {}

---@return ToolCall
function ToolCall:new(o)
    o = o or {}
    o.id = o.id or ""
    o.progress_messages = o.progress_messages or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---@param message string
function ToolCall:add_progress_message(message)
    table.insert(self.progress_messages, message)
end

---@return boolean
function ToolCall:is_done()
    -- FYI see run_tools_and_send_results_back_to_the_model() for when call_output is set
    return self.call_output ~= nil
end

function ToolCall:is_outstanding()
    return self.response_message == nil
end

-- FYI marker interface for now

return ToolCall
