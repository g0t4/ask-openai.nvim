local ansi = require("ask-openai.predictions.ansi")
local log = require("devtools.logs.logger").universal()

---@class RewritePerformance
---@field time_to_first_token_ms? number
---@field rag_duration_ms? number
---@field total_duration_ms? number
local RewritePerformance = {}
RewritePerformance.__index = RewritePerformance

function RewritePerformance:new()
    self._rewrite_start_time_ns = get_time_in_ns()

    self._rag_start_time_ns = nil
    self.rag_duration_ms = nil

    self.time_to_first_token_ms = nil

    self.total_duration_ms = nil
    return self
end

function RewritePerformance:token_arrived()
    if self.time_to_first_token_ms ~= nil then
        return
    end
    self.time_to_first_token_ms = get_elapsed_time_in_rounded_ms(self._rewrite_start_time_ns)
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
--- @param num_deltas_content number
--- @param num_deltas_reasoning number
---@return number|nil
function RewritePerformance:tokens_per_second(num_deltas_content, num_deltas_reasoning)
    local total_deltas = num_deltas_content + num_deltas_reasoning
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

return RewritePerformance
