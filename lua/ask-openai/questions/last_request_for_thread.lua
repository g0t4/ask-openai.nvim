local LastRequest = require("ask-openai.backends.last_request")

---@class LastRequestForThread : LastRequest
---@field thread ChatThread
---@field accumulated_model_response_messages RxAccumulatedMessage[] -- model "assistant" responses, built from SSEs
local LastRequestForThread = {}

---@param thread ChatThread
function LastRequestForThread:new(thread)
    self = setmetatable({}, { __index = self })
    self.thread = nil -- PRN? pass thread in ctor?
    self.accumulated_model_response_messages = {}
    return self
end

return LastRequestForThread
