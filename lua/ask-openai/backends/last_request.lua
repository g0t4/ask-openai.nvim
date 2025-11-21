local log = require("ask-openai.logs.logger").predictions()

---@class LastRequest
---@field body table
---@field handle? uv.uv_process_t
---@field pid? integer
---@field start_time integer -- unix timestamp when request was sent (for timing)
---@field marks_ns_id
local LastRequest = {}
local request_counter = 1

---@param body table<string, any>
---@return LastRequest
function LastRequest:new(body)
    self = setmetatable({}, { __index = self })
    self.body = body
    self.handle = nil
    self.pid = nil
    self.start_time = os.time()
    self.marks_ns_id = vim.api.nvim_create_namespace("ask.marks." .. request_counter)
    request_counter = request_counter + 1
    return self
end

function LastRequest.terminate(self)
    if self == nil or self.handle == nil then
        -- FYI self == nil check so I can call w/o check nil using:
        --   LastRequest.terminate(request)
        --   instead of request:terminate()   -- would blow up on nil
        return
    end

    local handle = self.handle
    local pid = self.pid
    self.handle = nil
    self.pid = nil
    if handle ~= nil and not handle:is_closing() then
        -- log:trace("Terminating process, pid: ", pid)

        handle:kill("sigterm")
        handle:close()
    end
end

return LastRequest
