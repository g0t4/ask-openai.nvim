-- Preserve server fields without translating their units or semantics.
local M = {}

function M.is_final(sse)
    return type(sse.timings) == "table"
        or (type(sse.usage) == "table" and type(sse.choices) == "table" and next(sse.choices) == nil)
end

function M.copy(sse, message)
    for _, field in ipairs({ "timings", "usage", "metrics" }) do
        if sse[field] ~= nil then
            message[field] = sse[field]
        end
    end
end

-- Usage on an empty-choices chunk describes the request. Attribute it to a
-- message only for the single-choice requests we currently send.
function M.capture_final(sse, messages)
    if not M.is_final(sse) or type(sse.choices) ~= "table" or next(sse.choices) ~= nil then
        return false
    end
    if messages and #messages == 1 then
        messages[1].last_sse = sse
        return true
    end
    return false
end

return M
