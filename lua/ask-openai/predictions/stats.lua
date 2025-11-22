local api = require("ask-openai.api")
local llamacpp_stats = require("ask-openai.backends.llama_cpp.stats")
local log = require("ask-openai.logs.logger").predictions()
local lualine = require("ask-openai.status.lualine")

local M = {}

---@param sse table
---@param perf FIMPerformance
function M.show_prediction_stats(sse, perf)
    local stats = llamacpp_stats.parse_llamacpp_stats(sse)
    if not stats then
        return
    end

    lualine.set_last_fim_stats(stats)
    if not api.are_notify_stats_enabled() then
        -- log:luaify_trace("stats", sse.timings)
        return
    end

    local messages = {}
    table.insert(messages, "FIM Stats")
    table.insert(messages, string.format("in: %d tokens @ %.2f tokens/sec", stats.prompt_tokens, stats.prompt_tokens_per_second))
    table.insert(messages, string.format("out: %d tokens @ %.2f tokens/sec", stats.predicted_tokens, stats.predicted_tokens_per_second))

    if stats.cached_tokens ~= nil then
        table.insert(messages, string.format("cached: %d tokens", stats.cached_tokens))
    end

    if stats.draft_tokens ~= nil then
        local pct = 0
        if stats.draft_tokens > 0 then
            pct = (stats.draft_tokens_accepted / stats.draft_tokens) * 100
        end
        table.insert(messages, string.format("draft: %d tokens, %d accepted (%.2f%%)", stats.draft_tokens, stats.draft_tokens_accepted, pct))
    end

    if stats.truncated_warning ~= nil then
        table.insert(messages, string.format("truncated: %s", stats.truncated_warning))
    end

    if sse.generation_settings then
        local gen = sse.generation_settings
        table.insert(messages, "") -- blank line to split out gen inputs
        -- temperature
        table.insert(messages, string.format("temperature: %.2f", gen.temperature))
        -- top_p
        table.insert(messages, string.format("top_p: %.2f", gen.top_p))
        -- max_tokens
        table.insert(messages, string.format("max_tokens: %d", gen.max_tokens))
    end

    -- * timing
    if perf ~= nil then
        perf:overall_done()
        table.insert(messages, "\n")
        if perf.rag_duration_ms ~= nil then
            table.insert(messages, "RAG: " .. perf.rag_duration_ms .. " ms")
        end
        if perf.time_to_first_token_ms ~= nil then
            table.insert(messages, "TTFT: " .. perf.time_to_first_token_ms .. " ms")
        end
        if perf:TTFT_minus_RAG_ms() ~= nil then
            table.insert(messages, "  w/o RAG: " .. perf:TTFT_minus_RAG_ms() .. " ms")
        end
        if perf.total_duration_ms ~= nil then
            table.insert(messages, "Total: " .. perf.total_duration_ms .. " ms")
        end
    end

    local message = table.concat(messages, "\n")

    local notify = require("notify")
    if notify then
        -- if using nvim-notify, then clear prior notifications
        notify.dismiss({ pending = true, silent = true })
    end
    vim.notify(message, vim.log.levels.INFO, { title = "FIM Stats" })
end

return M
