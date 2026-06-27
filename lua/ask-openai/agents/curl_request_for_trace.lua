local CurlRequest = require("ask-openai.backends.curl_request")

---@class CurlRequestForTrace : CurlRequest
---@field trace AgentTrace
---@field already_sent boolean
---@field accumulated_model_response_messages RxAccumulatedMessage[] -- AIMessage response message(s), built from SSEs... while this is setup to support multiple AIMessages from the model on a single completion request, in practice it's only ever one... just did this to support multiple should that ever happen... or even if the SSEs are messed up somehow and split across multiple accidentally
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
