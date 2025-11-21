local LastRequest = require("ask-openai.backends.last_request")

---@class LastRequestForThread : LastRequest
---@field thread ChatThread
---@field accumulated_model_response_messages RxAccumulatedMessage[] -- model "assistant" responses, built from SSEs
local LastRequestForThread = {}
local class_mt = { __index = LastRequest } -- inherit from LastRequest (for reals, not just the type annotations :] )
setmetatable(LastRequestForThread, class_mt)

---@param body table<string, any>
---@param base_url string
---@param endpoint CompletionsEndpoints
---@return LastRequestForThread
function LastRequestForThread:new(body, base_url, endpoint)
    me = self -- making it obvious this is passing LastRequestForThread as self (key for inheritance to work)
    self = LastRequest.new(me, body, base_url, endpoint) --[[@as LastRequestForThread]]

    self.thread = nil
    self.accumulated_model_response_messages = {}
    -- TODO do thread/accumulated_model_response_messages even belong on the LastRequestForThread?
    --   IOTW should I just use LastRequest and put them elsewhere?

    return self
end

function LastRequestForThread:test()
    -- TODO use this when you add your first method to LastRequestForThread
    --  this is a placeholder for my inheritance test case
end

return LastRequestForThread
