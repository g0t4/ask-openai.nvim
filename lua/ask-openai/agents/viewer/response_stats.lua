-- Display raw backend statistics without treating unlike timing fields as aliases.
local M = {}
local HLGroups = require("ask-openai.hlgroups")
local response_speculative = require("ask-openai.backends.response_speculative")

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
        text = text .. string.format(" @ %.1f%%", acceptance_rate * 100)
    end
    parts[#parts + 1] = text
end

function M.format(response)
    response = object(response)
    local counts, timing_parts, output_details = {}, {}, {}
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
        add_draft(output_details, timings.draft_n, timings.draft_n_accepted)
    else
        local usage, metrics = object(response.usage), object(response.metrics)
        local prompt_details = object(usage.prompt_tokens_details)
        add_number(counts, "cached: ", prompt_details.cached_tokens)
        if type(usage.prompt_tokens) == "number" and type(prompt_details.cached_tokens) == "number"
            and prompt_details.cached_tokens >= 0 and prompt_details.cached_tokens <= usage.prompt_tokens then
            add_number(counts, "in: ", usage.prompt_tokens - prompt_details.cached_tokens)
        else
            add_number(counts, "in (includes cached): ", usage.prompt_tokens)
        end
        add_number(counts, "out: ", usage.completion_tokens)
        local reasoning_tokens = object(usage.completion_tokens_details).reasoning_tokens or usage.reasoning_tokens
        if type(reasoning_tokens) == "number" and reasoning_tokens > 0 then
            add_number(output_details, "reasoning: ", reasoning_tokens)
        end
        local proposed, accepted, rate, mean = response_speculative.get(response)
        add_draft(output_details, proposed, accepted, rate)
        add_number(output_details, "  mean acceptance length: ", mean, "%.2f")
        add_number(timing_parts, "TTFT: ", metrics.time_to_first_token_ms, "%.1f ms")
        if type(metrics.queue_time_ms) == "number" and metrics.queue_time_ms >= 0.05 then
            add_number(timing_parts, "queue: ", metrics.queue_time_ms, "%.1f ms")
        end
        add_number(output_details, "decode: ", metrics.generation_time_ms, "%.1f ms")
        add_number(output_details, "mean ITL: ", metrics.mean_itl_ms, "%.1f ms")
    end
    local lines = {}
    if #counts > 0 then lines[#lines + 1] = table.concat(counts, " | ") end
    for _, text in ipairs(output_details) do lines[#lines + 1] = "  " .. text end
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
