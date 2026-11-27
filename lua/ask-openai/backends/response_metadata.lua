local log = require("devtools.logs.logger").universal()

-- Preserve server fields without translating their units or semantics.
local M = {}

function M.accumulate(sse, accumulated_message)
    -- FYI safe to assume timings are always present in our deployment standards
    --  so do not bother with finish_reason as a part of being "done"... b/c that always comes before timings anyways
    -- FYI model is on SSE level for sglang, llama-server and vllm

    -- * preserve fields
    for _, field in ipairs({ "timings", "usage", "metrics", "sglext", "backend", "model" }) do
        -- do not ever treat nil/vim.NIL as a value that we set
        if sse[field] ~= nil and sse[field] ~= vim.NIL then
            if accumulated_message[field] ~= nil and accumulated_message[field] ~= sse[field] then
                -- checking if value is new => we shouldn't ever see a different value per field and really shouldn't be seeing any field twice (in diff SSEs anyways)...
                --   we could see it twice if we call this copy() repeatedly
                log:error("YIKES message['" .. field .. "'] already set with: ", accumulated_message[field], "will replace with:  ", sse[field])
            end
            accumulated_message[field] = sse[field]
        end
    end

    -- * determinbe backend+done
    -- I am not thrilled about needing to append `done` but... not the end of the world
    --  TODO move all this to metadata and not message level or on a record level?
    if accumulated_message.done == nil then
        local has_sglang_timings = (type(sse.timings) == "table" and type(sse.timings.choices) == "table")
        local has_llama_server_timings = type(sse.timings) == "table" and sse.timings.choices == nil
        local has_usage = type(sse.usage) == "table"
        local has_sglext = type(sse.sglext) == "table"
        local has_metrics = type(sse.metrics) == "table"

        -- * ONLY set backend when done so I don't have to store done too
        if has_sglext and has_sglang_timings and has_usage then
            -- FYI must have sglext is enough (our extension)
            -- OR, timings.choices if we dont have our extension but our extension is going to be the deployment standard going forward so this is less important
            accumulated_message.backend = "sglang"
            accumulated_message.done = true
        elseif has_metrics and has_usage then
            -- FYI system_fingerprint is redundant to check b/c metrics+usage tells us this
            -- and sse.system_fingerprint and sse.system_fingerprint:find("^vllm")
            accumulated_message.backend = "vllm"
            accumulated_message.done = true
        elseif has_llama_server_timings and not has_sglext then
            accumulated_message.backend = "llama-server"
            accumulated_message.done = true
        end
    else
        log:info("backend already set, unexpected... not a problem just you wanted to know", sse)
    end
end

return M
