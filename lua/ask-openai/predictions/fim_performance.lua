local ansi = require("ask-openai.predictions.ansi")
local log = require("ask-openai.logs.logger").predictions()

-- TODO track thinking time? and merge thinking dots logic into here
-- TODO turn this into FIMState too? and use for UX updates, i.e.
--   request started (before anything sent)
--   RAG sent/pending
--   FIM sent/pending
--   Thinking started
--   Content started
--   Finished
--   (other states/perf/timing too)

---@class FIMPerformance
---@field time_to_first_token_ms? number
---@field rag_duration_ms? number
---@field total_duration_ms? number
local FIMPerformance = {}
FIMPerformance.__index = FIMPerformance

function FIMPerformance:new()
    self._prediction_start_time_ns = get_time_in_ns()

    self._rag_start_time_ns = nil
    self.rag_duration_ms = nil

    self.time_to_first_token_ms = nil

    self.total_duration_ms = nil
    return self
end

function FIMPerformance:token_arrived()
    if self.time_to_first_token_ms ~= nil then
        return
    end
    self.time_to_first_token_ms = get_elapsed_time_in_rounded_ms(self._prediction_start_time_ns)
end

function FIMPerformance:rag_started()
    if self._rag_start_time_ns ~= nil then
        error("rag called a second time, aborting...")
    end
    self._rag_start_time_ns = get_time_in_ns()
end

function FIMPerformance:rag_done()
    -- FYI add this back when you can repro the random bug with rag_done called twice?
    --  it was happeningg but I can't repro it
    --  seems to be that bug that sometimes happens when starting up and adding blank lines and canceling quickly
    --  I wonder if somehoww rag_done is dispatched right when I am canceling and if the two happen to call back to this
    --    TODO also enable logging in on_rag_response... which calls this, and yes if that is called both for cancel and done, then that would explain double call here
    -- log:info("rag_done called, start has rag_duration_ms: '" .. vim.inspect(self.rag_duration_ms) .. "'")
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

function FIMPerformance:overall_done()
    if self.total_duration_ms ~= nil then
        error("completed called a second time, timings might be wrong, aborting...")
    end
    self.total_duration_ms = get_elapsed_time_in_rounded_ms(self._prediction_start_time_ns)

    local message = "FIMPerformance - "
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

function FIMPerformance:TTFT_minus_RAG_ms()
    if self.time_to_first_token_ms == nil then
        return nil
    end
    if self.rag_duration_ms == nil then
        return nil
    end
    return self.time_to_first_token_ms - self.rag_duration_ms
end

return FIMPerformance
