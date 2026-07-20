local ansi = require("ask-openai.predictions.ansi")
local log = require("devtools.logs.logger").universal()

---@class RewritePerformance
---@field time_to_first_token_ms? number
---@field rag_duration_ms? number
---@field total_duration_ms? number
---@field num_deltas_reasoning = 0
---@field num_deltas_content = 0
local RewritePerformance = {}
RewritePerformance.__index = RewritePerformance

function RewritePerformance:new()
    self = setmetatable({}, RewritePerformance)

    self._rewrite_start_time_ns = get_time_in_ns()

    self._rag_start_time_ns = nil
    self.rag_duration_ms = nil

    self.time_to_first_token_ms = nil

    self.total_duration_ms = nil

    self.num_deltas_reasoning = 0
    self.num_deltas_content = 0

    return self
end

function RewritePerformance:token_arrived(chunk, reasoning_chunk)
    -- PRN I could track status here too (i.e. natural fit to track rag start/done, completion start/thinking/completing/done, etc)
    if chunk ~= "" then
        self.num_deltas_content = self.num_deltas_content + 1
    end
    if reasoning_chunk ~= "" then
        self.num_deltas_reasoning = self.num_deltas_reasoning + 1
    end

    -- todo if set
    if self.time_to_first_token_ms == nil then
        self.time_to_first_token_ms = get_elapsed_time_in_rounded_ms(self._rewrite_start_time_ns)
    end
end

--- Called when RAG query starts
function RewritePerformance:rag_started()
    if self._rag_start_time_ns ~= nil then
        error("rag_started called a second time, aborting...")
    end
    self._rag_start_time_ns = get_time_in_ns()
end

--- Called when RAG query completes
function RewritePerformance:rag_done()
    if self.rag_duration_ms ~= nil then
        local message = "rag_done might have been called twice b/c " .. vim.inspect(self.rag_duration_ms) .. " is NOT NIL when it should be, timings might be wrong, aborting..."
        log:error(message)
        error(message)
    end
    if self._rag_start_time_ns == nil then
        error("rag_done called before rag_started, aborting...")
    end
    self.rag_duration_ms = get_elapsed_time_in_rounded_ms(self._rag_start_time_ns)
end

--- Called when the rewrite completes (accept or cancel)
function RewritePerformance:overall_done()
    if self.total_duration_ms ~= nil then
        error("completed called a second time, timings might be wrong, aborting...")
    end
    self.total_duration_ms = get_elapsed_time_in_rounded_ms(self._rewrite_start_time_ns)

    local message = "RewritePerformance - "
    if self.time_to_first_token_ms then
        message = message .. "TTFT: " .. ansi.underline(self.time_to_first_token_ms .. " ms") .. " "
    end
    if self.rag_duration_ms then
        message = message .. "RAG: " .. ansi.underline(self.rag_duration_ms .. " ms") .. " "
    end
    if self.total_duration_ms then
        message = message .. "TOTAL: " .. ansi.underline(self.total_duration_ms .. " ms")
    end
    log:info(message)

    return message
end

--- Returns the time from RAG completion to first token (if both are available)
function RewritePerformance:ttft_minus_rag_ms()
    if self.time_to_first_token_ms == nil then
        return nil
    end
    if self.rag_duration_ms == nil then
        return nil
    end
    return self.time_to_first_token_ms - self.rag_duration_ms
end

--- Computes estimated tokens_per_second based on delta counts and elapsed time.
--- Automatically subtracts RAG duration from total elapsed time, since tok/sec
--- is meant to measure completion speed only.
---@return number|nil
function RewritePerformance:tokens_per_second()
    local total_deltas = self.num_deltas_content + self.num_deltas_reasoning
    if total_deltas == 0 then
        return 0
    end

    local elapsed_ns = get_time_in_ns() - self._rewrite_start_time_ns
    if elapsed_ns <= 0 then
        return 0
    end

    local elapsed_seconds = elapsed_ns / 1e9

    -- Subtract RAG duration from total time to isolate completion speed
    if self.rag_duration_ms ~= nil and self.rag_duration_ms > 0 then
        elapsed_seconds = elapsed_seconds - (self.rag_duration_ms / 1000)
    end

    if elapsed_seconds <= 0 then
        return 0 -- avoid division by zero or negative time
    end

    return total_deltas / elapsed_seconds
end

function RewritePerformance:preview_summary()
    local dots = require("ask-openai.frontends.thinking.dots")

    local parts = {
        dots:get_still_thinking_message_from_ns(self._rewrite_start_time_ns),

        -- show reasoning count during preview since we don't show reasoning tokens
        tostring(self.num_deltas_reasoning),
    }

    local tok_per_sec = self:tokens_per_second()
    if tok_per_sec > 0 then
        local speed = string.format("~%.0f tok/sec", tok_per_sec)
        table.insert(parts, speed)
    end

    return parts
end

return RewritePerformance
