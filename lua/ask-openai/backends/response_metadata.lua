-- Preserve server fields without translating their units or semantics.
local M = {}

function M.is_final(sse)
    for _, choice in ipairs(type(sse.choices) == "table" and sse.choices or {}) do
        if type(choice) == "table" and choice.finish_reason ~= nil and choice.finish_reason ~= vim.NIL then
            return true
        end
    end
    return type(sse.timings) == "table"
        or ((type(sse.usage) == "table" or type(sse.sglext) == "table" or type(sse.meta_info) == "table")
            and type(sse.choices) == "table" and next(sse.choices) == nil)
end

function M.copy(sse, message)
    for _, field in ipairs({ "timings", "usage", "metrics", "sglext", "meta_info", "response_backend" }) do
        if sse[field] ~= nil and (sse[field] ~= vim.NIL or message[field] == nil) then
            message[field] = sse[field]
        end
    end
    if type(sse.sglext) == "table" or type(sse.meta_info) == "table"
        or (type(sse.usage) == "table" and sse.usage.reasoning_tokens ~= nil) then
        message.response_backend = "sglang"
    end
end

-- SGLang emits extensions and usage in separate terminal chunks. Preserve both
-- without mutating either raw SSE object or letting null placeholders erase data.
function M.merge(previous, sse)
    local merged = {}
    for key, value in pairs(previous or {}) do merged[key] = value end
    for key, value in pairs(sse) do
        if value ~= vim.NIL or merged[key] == nil then merged[key] = value end
    end
    M.copy(sse, merged)
    return merged
end

-- Usage on an empty-choices chunk describes the request. Attribute it to a
-- message only for the single-choice requests we currently send.
function M.capture_final(sse, messages)
    if not M.is_final(sse) or type(sse.choices) ~= "table" or next(sse.choices) ~= nil then
        return false
    end
    if messages and #messages == 1 then
        messages[1].last_sse = messages[1].last_sse and M.merge(messages[1].last_sse, sse) or sse
        return true
    end
    return false
end

return M
