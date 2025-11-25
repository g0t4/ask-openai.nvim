local LastRequest = require("ask-openai.backends.last_request")

---@class CurlRequestForThread : LastRequest
---@field thread ChatThread
---@field accumulated_model_response_messages RxAccumulatedMessage[] -- model "assistant" responses, built from SSEs
local CurlRequestForThread = {}
local class_mt = { __index = LastRequest } -- inherit from LastRequest (for reals, not just the type annotations :] )
setmetatable(CurlRequestForThread, class_mt)

---@param params LastRequestParams
---@return CurlRequestForThread
function CurlRequestForThread:new(params)
    local me = self -- making it obvious this is passing CurlRequestForThread as self (key for inheritance to work)
    self = LastRequest.new(me, params) --[[@as CurlRequestForThread]]

    self.thread = nil
    self.accumulated_model_response_messages = {}
    -- TODO do thread/accumulated_model_response_messages even belong on the CurlRequestForThread?
    --   IOTW should I just use LastRequest and put them elsewhere?

    return self
end

function CurlRequestForThread:test()
    -- TODO use this when you add your first method to CurlRequestForThread
    --  this is a placeholder for my inheritance test case
end

return CurlRequestForThread
