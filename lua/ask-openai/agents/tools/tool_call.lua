--- FYI MUST MIRROR OpeanAI format b/c this will get sent back
---   i.e. that means function is a nested object
---@class ToolCall : OpenAIChoiceDeltaToolCall
---
---  my additions:
---@field arguments_error? string
---@field response_message table|nil -- TODO type this? response message to send call results back to the model that will, also attached to agent_trace (history)
---@field call_output? ToolCallOutput -- tool call outputs (specific to a given tool type, some have standard structure, i.e. MCP)
---@field progress_notifications string[] -- progress messages received during tool execution
---@field start_time_ms integer -- timestamp (ms) when tool execution began (set by frontend before calling tool)
local ToolCall = {}

---@return ToolCall
function ToolCall:new(o)
    o = o or {}
    o.id = o.id or ""
    o.progress_notifications = o.progress_notifications or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Validate only after the final delta. Partial argument strings are normal while streaming.
function ToolCall:flag_invalid_arguments()
    local arguments = self["function"].arguments
    if type(arguments) ~= "string" or not arguments:match("^%s*{") or not pcall(vim.json.decode, arguments) then
        self.arguments_error = "Tool was not run. Retry with arguments encoded as a valid JSON object."
    end
end

---@param notification string
function ToolCall:add_progress_notification(notification)
    table.insert(self.progress_notifications, notification) -- TODO track full object not just stringified?
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
