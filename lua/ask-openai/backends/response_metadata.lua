local log = require("devtools.logs.logger").universal()

-- Preserve server fields without translating their units or semantics.
local M = {}

function M.accumulate_metadata(sse, accumulated_message)
    -- FYI safe to assume timings are always present in our deployment standards
    --  so do not bother with finish_reason as a part of being "done"... b/c that always comes before timings anyways
    -- FYI model is on SSE level for sglang, llama-server and vllm

    -- ensure metadata exists
    accumulated_message.metadata = accumulated_message.metadata or {}
    metadata = accumulated_message.metadata

    -- * preserve fields
    for _, field in ipairs({ "timings", "usage", "metrics", "sglext", "backend", "model" }) do
        -- do not ever treat nil/vim.NIL as a value that we set
        if sse[field] ~= nil and sse[field] ~= vim.NIL then
            if metadata[field] ~= nil and metadata[field] ~= sse[field] then
                -- checking if value is new => we shouldn't ever see a different value per field and really shouldn't be seeing any field twice (in diff SSEs anyways)...
                --   we could see it twice if we call this copy() repeatedly
                log:error("YIKES message['" .. field .. "'] already set with: ", metadata[field], "will replace with:  ", sse[field])
            end
            metadata[field] = sse[field]
        end
    end

    -- * determinbe backend+done
    -- I am not thrilled about needing to append `done` but... not the end of the world
    --  TODO move all this to metadata and not message level or on a record level?
    if metadata.done ~= nil then
        return
    end

    local has_sglang_timings = (type(metadata.timings) == "table" and type(metadata.timings.choices) == "table")
    local has_llama_server_timings = type(metadata.timings) == "table" and metadata.timings.choices == nil
    local has_usage = type(metadata.usage) == "table"
    local has_sglext = type(metadata.sglext) == "table"
    local has_metrics = type(metadata.metrics) == "table"

    -- * ONLY set backend when done so I don't have to store done too
    if has_sglext and has_sglang_timings and has_usage then
        -- FYI must have sglext is enough (our extension)
        -- OR, timings.choices if we dont have our extension but our extension is going to be the deployment standard going forward so this is less important
        metadata.backend = "sglang"
        metadata.done = true
    elseif has_metrics and has_usage then
        -- FYI system_fingerprint is redundant to check b/c metrics+usage tells us this
        -- and metadata.system_fingerprint and metadata.system_fingerprint:find("^vllm")
        metadata.backend = "vllm"
        metadata.done = true
    elseif has_llama_server_timings and not has_sglext then
        metadata.backend = "llama-server"
        metadata.done = true
    end

end

return M
