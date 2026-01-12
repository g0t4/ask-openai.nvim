local log = require("ask-openai.logs.logger").predictions()

local M = {}

--- * consistent failure logs
--- callers should focus on handling errors, not on recording them!
function M.xpcall_log_failures(error_message)
    local trace = debug.traceback("safely.xpcall_log_failures", 3)
    log:error("on_xpcall_error.message", error_message)
    log:error("on_xpcall_error.traceback", trace)
    return {
        -- this is returned to callers of xpcall
        -- normally you'd only get the error_message with .pcall()
        -- now callers get message and traceback
        message = error_message,
        traceback = trace
    }
end

function M.decode_json(json_string)
    local success, object = xpcall(vim.json.decode, M.xpcall_log_failures, json_string)
    if not success then
        log:error("failed to decode json: ", json_string)
    end
    return success, object
end

function M.decode_json_always_logged(json_string)
    local success, object = M.decode_json(json_string)
    if success then
        -- * key difference, this logs success too:
        log:info("decoded object: " .. vim.inspect(object))
    end
    return success, object
end

function M.decode_yaml(yaml_string)
    local function load()
        -- embed require call too, that way if lyaml is not installed locally, that gets logged too
        local lyaml = require("lyaml")
        lyaml.load(yaml_string)
    end
    local success, object = xpcall(load, M.xpcall_log_failures)
    if not success then
        log:error("failed to decode yaml: ", yaml_string)
    end
    return success, object
end

--- call function with xpcall and log failures
--- callers can focus on handling errors, not recording them
---
---@param what     async fun(...):...
---@return boolean success
---@return any result
---@return any ...
function M.call(what, ...)
    return xpcall(what, M.xpcall_log_failures, ...)
end

return M
