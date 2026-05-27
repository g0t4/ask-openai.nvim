local CurlRequest = require("ask-openai.backends.curl_request")

---@class CurlRequestForTrace : CurlRequest
---@field trace AgentTrace
---@field already_sent boolean
---@field accumulated_model_response_messages RxAccumulatedMessage[] -- model "assistant" responses, built from SSEs
local CurlRequestForTrace = {}
local class_mt = { __index = CurlRequest } -- inherit from CurlRequest (for reals, not just the type annotations :] )
setmetatable(CurlRequestForTrace, class_mt)

---@param params CurlRequestParams
---@return CurlRequestForTrace
function CurlRequestForTrace:new(params)
    local me = self -- making it obvious this is passing CurlRequestForTrace as self (key for inheritance to work)
    self = CurlRequest.new(me, params) --[[@as CurlRequestForTrace]]

    self.trace = nil
    self.already_sent = false
    self.accumulated_model_response_messages = {}
    return self
end

function CurlRequestForTrace:any_outstanding_tool_calls()
    return vim.iter(self.accumulated_model_response_messages or {}):any(function(rx_message)
        return vim.iter(rx_message.tool_calls):any(function(tool_call)
            return tool_call:is_outstanding()
        end)
    end)
end

return CurlRequestForTrace
