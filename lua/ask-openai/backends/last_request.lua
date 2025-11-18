local log = require("ask-openai.logs.logger").predictions()

---@class LastRequest
---@field body table
---@field handle uv_process_t
---@field pid integer
---@field thread ChatThread
---@field accumulated_model_response_messages ChatMessage[] -- model responses, built from SSEs (these are not sent back in follow up / tool results ... instead these are mapped to ChatThread.messages
---@field start_time integer -- unix timestamp when request was sent (for timing)
---@field marks_ns_id
local LastRequest = {}

local request_counter = 1
--- @param body table<string, any>
--- @return LastRequest
function LastRequest:new(body)
    self = setmetatable({}, { __index = LastRequest })
    -- PRN some connection back to the thread its a part of so it can communicate status changes (i.e. after termination)
    -- self.thread = thread -- ??
    self.body = body
    self.handle = nil
    self.pid = nil
    self.thread = nil -- TODO pass thread in ctor?
    self.accumulated_model_response_messages = {}
    self.start_time = os.time()
    self.marks_ns_id = vim.api.nvim_create_namespace("ask.marks." .. request_counter)
    request_counter = request_counter + 1
    return self
end

-- TODO status of request!

function LastRequest:terminate()
    -- PRN don't terminate if already terminated/completed (done)

    if self == nil or self.handle == nil then
        -- FYI self == nil check so I can call w/o check nil using:
        --   LastRequest.terminate(request)
        --   instead of request:terminate()   -- would blow up on nil
        return
    end

    -- PRN if I track status I don't need to ever clear the handle/pid
    local handle = self.handle
    local pid = self.pid
    self.handle = nil
    self.pid = nil
    if handle ~= nil and not handle:is_closing() then
        log:trace("Terminating process, pid: ", pid)

        -- PRN :h uv.spawn() for using uv.shutdown/uv.close? and fallback to kill, or does it matter?
        --   i.e. a callback when its shutdown?

        handle:kill("sigterm")
        handle:close()
        -- FYI ollama should show that connection closed/aborted
    end
end

return LastRequest
