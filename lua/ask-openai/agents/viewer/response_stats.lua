-- Display raw backend statistics without treating unlike timing fields as aliases.
local M = {}
local HLGroups = require("ask-openai.hlgroups")

local function object(value)
    return type(value) == "table" and value or {}
end

local function add_number(parts, label, value, format)
    if type(value) == "number" then
        parts[#parts + 1] = label .. string.format(format or "%d", value)
    end
end

local function add_draft(parts, proposed, accepted, acceptance_rate)
    if type(proposed) ~= "number" then return end
    local text = "draft: " .. proposed
    if type(accepted) == "number" then
        text = string.format("draft: %d/%d accepted", accepted, proposed)
        if type(acceptance_rate) ~= "number" and proposed > 0 then
            acceptance_rate = accepted / proposed
        end
    end
    if type(acceptance_rate) == "number" then
        text = text .. string.format(" @ %.0f%%", acceptance_rate * 100)
    end
    parts[#parts + 1] = text
end

function M.format(response)
    response = object(response)
    local counts, timing_parts = {}, {}
    if type(response.timings) == "table" then
        local timings = response.timings
        add_number(counts, "cached: ", timings.cache_n)
        for _, spec in ipairs({ { "in: ", "prompt_n", "prompt_per_second" },
            { "out: ", "predicted_n", "predicted_per_second" } }) do
            local count, rate = timings[spec[2]], timings[spec[3]]
            if type(count) == "number" then
                local text = spec[1] .. count
                if type(rate) == "number" and rate > 0 then text = text .. string.format(" @ %.0f tok/s", rate) end
                counts[#counts + 1] = text
            end
        end
        add_draft(counts, timings.draft_n, timings.draft_n_accepted)
    else
        local usage, metrics = object(response.usage), object(response.metrics)
        local prompt_details = object(usage.prompt_tokens_details)
        add_number(counts, "cached: ", prompt_details.cached_tokens)
        add_number(counts, "in (includes cached): ", usage.prompt_tokens)
        add_number(counts, "out: ", usage.completion_tokens)
        add_number(counts, "reasoning: ", object(usage.completion_tokens_details).reasoning_tokens)
        local speculative = object(metrics.speculative_decoding)
        add_draft(counts, speculative.num_draft_tokens, speculative.num_accepted_draft_tokens,
            speculative.draft_acceptance_rate)
        add_number(counts, "mean acceptance length: ", speculative.mean_acceptance_length, "%.2f")
        add_number(timing_parts, "TTFT: ", metrics.time_to_first_token_ms, "%.1f ms")
        add_number(timing_parts, "queue: ", metrics.queue_time_ms, "%.1f ms")
        add_number(timing_parts, "decode: ", metrics.generation_time_ms, "%.1f ms")
        add_number(timing_parts, "mean ITL: ", metrics.mean_itl_ms, "%.1f ms")
        -- vLLM's tokens_per_second includes prefill; it isn't decode throughput.
        add_number(timing_parts, "overall output: ", metrics.tokens_per_second, "%.1f tok/s")
    end
    local lines = {}
    if #counts > 0 then lines[#lines + 1] = table.concat(counts, " | ") end
    if #timing_parts > 0 then lines[#lines + 1] = table.concat(timing_parts, " | ") end
    return lines
end

function M.total_tokens(response)
    response = object(response)
    if type(response.timings) == "table" then
        local timings = response.timings
        return (timings.cache_n or 0) + (timings.prompt_n or 0) + (timings.predicted_n or 0)
    end
    local usage = object(response.usage)
    if type(usage.total_tokens) == "number" then return usage.total_tokens end
    if type(usage.prompt_tokens) == "number" and type(usage.completion_tokens) == "number" then
        return usage.prompt_tokens + usage.completion_tokens
    end
end

function M.render(lines, response)
    for _, text in ipairs(M.format(response)) do
        lines:append_styled_text(text, HLGroups.CHAT_REASONING)
    end
end

return M
