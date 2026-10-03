local log = require("devtools.logs.logger").universal()

---@class CurlRequest
---@field body table
---@field base_url string
---@field endpoint CompletionsEndpoints
---@field handle? uv.uv_process_t
---@field pid? integer
---@field start_time integer -- unix timestamp when request was sent (for timing)
---@field marks_ns_id integer
---@field type string
---@field tcp_handle uv.uv_tcp_t?
local CurlRequest = {}
local request_counter = 1

---@class CurlRequestParams
---@field body table<string, any>
---@field base_url string
---@field endpoint CompletionsEndpoints
---@field type string

---@param params CurlRequestParams
---@return CurlRequest
function CurlRequest:new(params)
    self = setmetatable({}, { __index = self })
    self.body = params.body
    self.endpoint = params.endpoint
    self.type = params.type or ""

    local base_url = params.base_url
    if base_url == nil or base_url == "" then
        error(string.format("base_url must be set, currently is: %q", base_url))
    end
    self.base_url = base_url

    self.handle = nil
    self.pid = nil
    self.start_time = os.time()
    self.marks_ns_id = vim.api.nvim_create_namespace("ask.marks." .. request_counter)
    request_counter = request_counter + 1
    return self
end

---@return string
function CurlRequest:get_url()
    return self.base_url .. self.endpoint
end

---@param request CurlRequest
function CurlRequest.terminate(request)
    if request ~= nil and request.tcp_handle ~= nil then
        log:info("close tcp_handle", request.tcp_handle)
        -- request.tcp_handle.is_closing -- TODO check is_closing first?
        local closing, isclosing_err, isclosing_err_name = request.tcp_handle:is_closing()
        if isclosing_err then
            -- TODO do I care about this? when would checking fail?
            log:warn("failed to check if tcp_handle:is_closing()", isclosing_err, isclosing_err_name)
        end
        if closing then
            -- warn if already closing
            log:error("ummm tcp_handle.is_closing() is true?!", request.tcp_handle)
        end

        request.tcp_handle:close()
        request.tcp_handle = nil
        return
    end

    -- *** legacy curl
    -- TODO! strip once I am happy with new approach (low level in-process)
    if request == nil or request.handle == nil then
        -- FYI prefer CurlRequest.terminate(request) b/c no error if request is nil
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

return CurlRequest
