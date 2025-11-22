local log = require("ask-openai.logs.logger").predictions()

---@class LastRequest
---@field body table
---@field base_url string
---@field endpoint CompletionsEndpoints
---@field handle? uv.uv_process_t
---@field pid? integer
---@field start_time integer -- unix timestamp when request was sent (for timing)
---@field marks_ns_id
local LastRequest = {}
local request_counter = 1

---@class LastRequestParams
---@field body table<string, any>
---@field base_url string
---@field endpoint CompletionsEndpoints

---@param params LastRequestParams
---@return LastRequest
function LastRequest:new(params)
    local body = params.body
    local base_url = params.base_url
    local endpoint = params.endpoint

    self = setmetatable({}, { __index = self })
    self.body = body

    if base_url == nil or base_url == "" then
        error(string.format("base_url must be set, currently is: %q", base_url))
    end
    self.base_url = base_url
    self.endpoint = endpoint

    self.handle = nil
    self.pid = nil
    self.start_time = os.time()
    self.marks_ns_id = vim.api.nvim_create_namespace("ask.marks." .. request_counter)
    request_counter = request_counter + 1
    return self
end

---@return string
function LastRequest:get_url()
    return self.base_url .. self.endpoint
end

function LastRequest.terminate(request)
    if request == nil or request.handle == nil then
        -- FYI prefer LastRequest.terminate(request) b/c no error if request is nil
        --   NOT request:terminate() -- get an error if request is nil
        return
    end

    -- FYI handle/pid (this entire request object) is PER literal request
    --  so no need to clear handle/pid
    local handle = request.handle
    if not handle:is_closing() then
        -- log:trace("Terminating process, pid: ", request.pid)
        -- sigterm is important to tell curl to stop the request, so the server doesn't keep generating!
        handle:kill("sigterm")
        handle:close()
    end
end

return LastRequest
