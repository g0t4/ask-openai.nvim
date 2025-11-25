local CurlRequest = require("ask-openai.backends.last_request")

---@class CurlRequestForThread : CurlRequest
---@field thread ChatThread
---@field accumulated_model_response_messages RxAccumulatedMessage[] -- model "assistant" responses, built from SSEs
local CurlRequestForThread = {}
local class_mt = { __index = CurlRequest } -- inherit from CurlRequest (for reals, not just the type annotations :] )
setmetatable(CurlRequestForThread, class_mt)

---@param params CurlRequestParams
---@return CurlRequestForThread
function CurlRequestForThread:new(params)
    local me = self -- making it obvious this is passing CurlRequestForThread as self (key for inheritance to work)
    self = CurlRequest.new(me, params) --[[@as CurlRequestForThread]]

    self.thread = nil
    self.accumulated_model_response_messages = {}
    -- TODO do thread/accumulated_model_response_messages even belong on the CurlRequestForThread?
    --   IOTW should I just use CurlRequest and put them elsewhere?

    return self
end

function CurlRequestForThread:test()
    -- TODO use this when you add your first method to CurlRequestForThread
    --  this is a placeholder for my inheritance test case
end

return CurlRequestForThread
