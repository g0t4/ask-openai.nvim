-- Display adapters only; raw server objects remain in saved traces.
local M = {}

local function ensure_table(value)
    -- FYI if value is not a table, it's basically dropped which is kinda ehhhh
    return type(value) == "table" and value or {}
end

function M.get(response)
    local speculative = ensure_table(ensure_table(response.metrics).speculative_decoding)
    if next(speculative) then
        return speculative.num_draft_tokens,
            speculative.num_accepted_draft_tokens,
            speculative.draft_acceptance_rate,
            speculative.mean_acceptance_length
    end
    local spec = ensure_table(ensure_table(response.sglext).spec_tokens_details)
    if not next(spec) then
        spec = ensure_table(response.meta_info)
    end
    return spec.spec_num_proposed_drafts,
        spec.spec_num_correct_drafts,
        spec.spec_accept_rate,
        spec.spec_accept_length
end

return M
