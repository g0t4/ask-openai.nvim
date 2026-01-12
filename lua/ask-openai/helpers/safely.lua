local log = require("ask-openai.logs.logger").predictions()

local M = {}

function M.xpcall_log_failures(message)
    -- * capture more than just the message
    -- consitent logging of failure details here, then consumers can merely focus on their context on an error (args they passed)
    local traceback = debug.traceback("foooo", 3)
    log:error("on_xpcall_error.message", message)
    log:error("on_xpcall_error.traceback", debug.traceback("on_xpcall_error", 3))
    return {
        message = message,
        traceback = traceback
    }
end

function M.decode_json(json_string)
    local decode = function()
        return vim.json.decode(json_string)
    end
    local success, object = xpcall(decode, M.xpcall_log_failures)
    if not success then
        log:error("failed to decode json: ", json_string)
    end
    return success, object
end

function M.decode_json_always_logged(json_string)
    local success, object = M.decode_json(json_string)
    if success then
        log:info("decoded object: " .. vim.inspect(object))
    end
    return success, object
end

return M
