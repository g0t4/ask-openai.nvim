local json = require("dkjson")

local M = {}

local function now_ms()
    return math.floor(vim.uv.hrtime() / 1000000)
end

local function next_trace_id()
    -- Wall time makes traces sortable/shareable; hrtime prevents collisions when
    -- Telescope completes several queries in the same millisecond.
    return string.format("%d%06d", os.time(), vim.uv.hrtime() % 1000000)
end

---@param source string
---@param request LSPSemanticGrepRequest
---@return table trace
function M.start(source, request)
    return {
        session_id = next_trace_id(),
        type = "rag",
        source = source,
        start_time = os.time(),
        _started_ms = now_ms(),
        request_body = vim.deepcopy(request),
    }
end

---@param trace table
---@param response table
---@return string? path
function M.save(trace, response)
    trace.duration_ms = now_ms() - trace._started_ms
    trace._started_ms = nil
    trace.response = response

    local save_dir = vim.fn.stdpath("state") .. "/ask-openai/rag/" .. trace.source
    vim.fn.mkdir(save_dir, "p")
    local path = save_dir .. "/" .. trace.session_id .. "-trace.json"
    local file, open_error = io.open(path, "w")
    if not file then
        return nil, open_error
    end

    file:write(json.encode(trace, {
        indent = true,
        exception = function(reason, bad_value, _, default_message)
            if reason == "unsupported type" and bad_value == vim.NIL then
                return "null"
            end
            return nil, default_message
        end,
    }))
    file:close()
    return path
end

return M
