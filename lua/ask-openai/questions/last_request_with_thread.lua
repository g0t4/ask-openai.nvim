local LastRequest = require("ask-openai.backends.last_request")
---@class LastRequestWithThread
---@field thread ChatThread
---@field last_request? LastRequest
local LastRequestWithThread = {}
---@param thread ChatThread
function LastRequestWithThread:new(thread)
    self = setmetatable({}, { __index = LastRequestWithThread })
    self.thread = thread
    self.last_request = nil
    return self
end

function LastRequestWithThread:get_last_request()
    return self.last_request
end

---set the last request
---@param request LastRequest
function LastRequestWithThread:set_last_request(request)
    self.last_request = request
end

return LastRequestWithThread
