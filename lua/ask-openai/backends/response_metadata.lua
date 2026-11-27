local log = require("devtools.logs.logger").universal()

-- Preserve server fields without translating their units or semantics.
local M = {}

function M.is_final(sse)
    local choices = type(sse.choices) == "table" and sse.choices or {}
    for _, choice in ipairs(choices) do
        local has_finish_reason = type(choice) == "table" and choice.finish_reason ~= nil and choice.finish_reason ~= vim.NIL
        if has_finish_reason then
            return true
        end
    end
    local has_timings = type(sse.timings) == "table"
    local has_usage = type(sse.usage) == "table"
    local has_sglext = type(sse.sglext) == "table"
    return has_timings
        or ((has_usage or has_sglext or type(sse.meta_info) == "table")
            and type(sse.choices) == "table" and next(sse.choices) == nil)
end

function M.copy(sse, message)
    -- log:info("copy", sse)
    for _, field in ipairs({ "timings", "usage", "metrics", "sglext", "meta_info", "response_backend" }) do
        if sse[field] ~= nil and (sse[field] ~= vim.NIL or message[field] == nil) then
            message[field] = sse[field]
        end
    end
    if message.response_backend == nil then
        -- TODO vet sglang marked
        -- TODO vet llama-server marked
        -- TODO vet vllm marked
        local timings_with_choices = (type(sse.timings) == "table" and type(sse.timings.choices) == "table")
        local timings_without_choices = type(sse.timings) == "table" and sse.timings.choices == nil
        local has_usage = type(sse.usage) == "table"
        local has_sglext = type(sse.sglext) == "table"
        local has_metrics = type(sse.metrics) == "table"

        if has_sglext and timings_with_choices and has_usage then
            -- FYI must have sglext + timings + usage to ensure you're using merged last_sse for sglang stats
            message.response_backend = "sglang"
        elseif has_metrics and sse.system_fingerprint and sse.system_fingerprint:find("^vllm") then
            message.response_backend = "vllm"
        elseif timings_without_choices and sse.sglext == nil then
            message.response_backend = "llama-server"
        end
    else
        log:info("response_backend already set, unexpected... not a problem just you wanted to know", sse)
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
