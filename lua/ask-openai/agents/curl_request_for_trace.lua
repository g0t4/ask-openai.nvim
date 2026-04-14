local CurlRequest = require("ask-openai.backends.curl_request")

---@class CurlRequestForTrace : CurlRequest
---@field trace AgentTrace
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
    self.accumulated_model_response_messages = {}
    -- TODO do trace/accumulated_model_response_messages even belong on the CurlRequestForTrace?
    --   IOTW should I just use CurlRequest and put them elsewhere?

    return self
end

function CurlRequestForTrace:test()
    -- TODO use this when you add your first method to CurlRequestForTrace
    --  this is a placeholder for my inheritance test case
end

return CurlRequestForTrace
