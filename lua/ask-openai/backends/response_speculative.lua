-- Display adapters only; raw server objects remain in saved traces.
local M = {}
local function object(value) return type(value) == "table" and value or {} end
function M.get(response)
    local speculative = object(object(response.metrics).speculative_decoding)
    if next(speculative) then
        return speculative.num_draft_tokens, speculative.num_accepted_draft_tokens,
            speculative.draft_acceptance_rate, speculative.mean_acceptance_length
    end
    local spec = object(object(response.sglext).spec_tokens_details)
    if not next(spec) then spec = object(response.meta_info) end
    return spec.spec_num_proposed_drafts, spec.spec_num_correct_drafts,
        spec.spec_accept_rate, spec.spec_accept_length
end
return M
