---@class SSEStats
---@field timings table?  -- llama-server timings object (for quick tests)
---@field prompt_tokens integer
---@field prompt_tokens_per_second number
---@field predicted_tokens integer
---@field predicted_tokens_per_second number
---@field cached_tokens integer?               # optional, may be nil
---@field draft_tokens integer?                # optional, may be nil
---@field draft_tokens_accepted integer?       # optional, may be nil
---@field truncated_warning string?            # optional, may be nil
---@field generation_settings table?           # extracted from parsed_sse.generation_settings, optional
---@field generation_settings.temperature number?
---@field generation_settings.top_p number?
---@field generation_settings.max_tokens integer?
local SSEStats = {}

function SSEStats:new()
    self = setmetatable({}, { __index = SSEStats })
    return self
end

local M = {}

---@param sse table
---@returns SSEStats?
function M.parse_llamacpp_stats(sse)
    -- *** currently only llama-server stats from its last SSE
    if not sse or not sse.timings then
        return
    end

    local timings = sse.timings
    local stats = SSEStats:new()

    -- commented out data is from example SSE
    -- "tokens_predicted": 7,
    -- "tokens_evaluated": 53,
    -- "has_new_line": false,
    -- "truncate": false,
    stats.truncated = sse.truncated
    -- * warn about truncated input
    if sse.truncated then
        local warning = "FIM Input Truncated!!!\n"

        local gen = sse.generation_settings
        if gen then
            -- "generation_settings": {
            --   "n_keep": 0,
            --   "n_discard": 0,
            if gen.n_keep ~= nil then
                warning = warning .. "\n  n_keep = " .. gen.n_keep
            end
            if gen.n_discard ~= nil then
                warning = warning .. "\n  n_discard = " .. gen.n_discard
            end
        end

        if timings.prompt_n then
            warning = warning .. "\n  timings.prompt_n = " .. timings.prompt_n
        end
        stats.truncated_warning = warning
        vim.notify(warning, vim.log.levels.WARN)
    end
    --
    -- "stop_type": "eos",
    -- "stopping_word": "",
    -- "tokens_cached": 59,
    -- TODO fallback on cache_n? I am using that currently from llama.cpp's server... does OpenAI use tokens_cached? if so take one or the other?
    stats.cached_tokens = timings.tokens_cached
    --
    -- "timings": {
    --   "prompt_n": 52,
    --   "prompt_ms": 33.474,
    --   "prompt_per_token_ms": 0.6437307692307692,
    --   "prompt_per_second": 1553.4444643603993,
    stats.prompt_tokens = timings.prompt_n
    stats.prompt_tokens_per_second = timings.prompt_per_second
    --   "predicted_n": 7,
    --   "predicted_ms": 51.669,
    --   "predicted_per_token_ms": 7.381285714285714,
    --   "predicted_per_second": 135.47775261762374,
    stats.predicted_tokens = timings.predicted_n
    stats.predicted_tokens_per_second = timings.predicted_per_second
    --   "draft_n": 3,
    --   "draft_n_accepted": 1
    stats.draft_tokens = timings.draft_n
    stats.draft_tokens_accepted = timings.draft_n_accepted
    -- }

    return stats
end

return M
