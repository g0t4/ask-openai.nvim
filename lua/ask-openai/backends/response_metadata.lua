local log = require("devtools.logs.logger").universal()

-- Preserve server fields without translating their units or semantics.
local M = {}

function M.accumulate(sse, message)
    -- log:info("copy", sse)
    -- FYI model is on SSE level for sglang, llama-server and vllm
    for _, field in ipairs({ "timings", "usage", "metrics", "sglext", "backend", "model" }) do
        -- do not ever treat nil/vim.NIL as a value that we set
        if sse[field] ~= nil and sse[field] ~= vim.NIL then
            if message[field] ~= nil and message[field] ~= sse[field] then
                -- checking if value is new => we shouldn't ever see a different value per field and really shouldn't be seeing any field twice (in diff SSEs anyways)...
                --   we could see it twice if we call this copy() repeatedly
                log:error("YIKES message['" .. field .. "'] already set with: ", message[field], "will replace with:  ", sse[field])
            end
            message[field] = sse[field]
        end
    end
    if message.backend == nil then
        -- TODO vet sglang marked
        -- TODO vet llama-server marked
        -- TODO vet vllm marked
        local timings_with_choices = (type(sse.timings) == "table" and type(sse.timings.choices) == "table")
        local timings_without_choices = type(sse.timings) == "table" and sse.timings.choices == nil
        local has_usage = type(sse.usage) == "table"
        local has_sglext = type(sse.sglext) == "table"
        local has_metrics = type(sse.metrics) == "table"

        if has_sglext or timings_with_choices then
            -- FYI must have sglext is enough (our extension)
            -- OR, timings.choices if we dont have our extension but our extension is going to be the deployment standard going forward so this is less important
            message.backend = "sglang"
        elseif has_metrics and sse.system_fingerprint and sse.system_fingerprint:find("^vllm") then
            message.backend = "vllm"
        elseif timings_without_choices and sse.sglext == nil then
            message.backend = "llama-server"
        end
    else
        log:info("backend already set, unexpected... not a problem just you wanted to know", sse)
    end
end

return M
