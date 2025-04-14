---
---@field body table
---@field handle uv_process_t
---@field pid integer
local LastRequest = {}

function LastRequest:new(body)
    self = setmetatable({}, { __index = LastRequest })
    self.body = body
    self.handle = nil
    self.pid = nil
    return self
end

return LastRequest
