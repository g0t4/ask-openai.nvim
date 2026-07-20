local ansi = require("ask-openai.predictions.ansi")
local log = require("devtools.logs.logger").universal()

---@class AgentTurnPerformance
---@field turn_index integer
---@field time_to_first_token_ms? number
---@field rag_duration_ms? number
---@field completion_duration_ms? number
---@field tokens_this_turn number
local AgentTurnPerformance = {}
AgentTurnPerformance.__index = AgentTurnPerformance

function AgentTurnPerformance:new(turn_index)
    -- TODO! THIS IS NOT REVIEWED AT ALL YET... I ASKED QWEN TO GET IT STARTED FOR ME TO THEN DO LATER
    self.turn_index = turn_index or 0
    self._turn_start_time_ns = get_time_in_ns()
    self._rag_start_time_ns = nil
    self.rag_duration_ms = nil
    self.time_to_first_token_ms = nil
    self.completion_duration_ms = nil
    self.tokens_this_turn = 0
    return self
end

function AgentTurnPerformance:token_arrived()
    if self.time_to_first_token_ms ~= nil then
        return
    end
    self.time_to_first_token_ms = get_elapsed_time_in_rounded_ms(self._turn_start_time_ns)
end

function AgentTurnPerformance:rag_started()
    if self._rag_start_time_ns ~= nil then
        error("rag_started called a second time for turn " .. self.turn_index .. ", aborting...")
    end
    self._rag_start_time_ns = get_time_in_ns()
end

function AgentTurnPerformance:rag_done()
    if self.rag_duration_ms ~= nil then
        local message = "rag_done might have been called twice for turn " .. self.turn_index .. ", aborting..."
        log:error(message)
        error(message)
    end
    if self._rag_start_time_ns == nil then
        error("rag_done called before rag_started for turn " .. self.turn_index .. ", aborting...")
    end
    self.rag_duration_ms = get_elapsed_time_in_rounded_ms(self._rag_start_time_ns)
end

function AgentTurnPerformance:completion_done()
    if self.completion_duration_ms ~= nil then
        error("completion_done called a second time for turn " .. self.turn_index .. ", aborting...")
    end
    self.completion_duration_ms = get_elapsed_time_in_rounded_ms(self._turn_start_time_ns)
end

function AgentTurnPerformance:ttft_minus_rag_ms()
    if self.time_to_first_token_ms == nil then
        return nil
    end
    if self.rag_duration_ms == nil then
        return nil
    end
    return self.time_to_first_token_ms - self.rag_duration_ms
end

function AgentTurnPerformance:tokens_per_second()
    if self.completion_duration_ms == nil or self.completion_duration_ms <= 0 then
        return 0
    end

    local elapsed_seconds = self.completion_duration_ms / 1000

    -- Subtract RAG duration from total time to isolate completion speed
    if self.rag_duration_ms ~= nil and self.rag_duration_ms > 0 then
        elapsed_seconds = elapsed_seconds - (self.rag_duration_ms / 1000)
    end

    if elapsed_seconds <= 0 then
        return 0
    end

    return self.tokens_this_turn / elapsed_seconds
end

--- Logs summary for this turn
function AgentTurnPerformance:log_summary()
    local message = "Turn " .. self.turn_index .. " - "
    if self.time_to_first_token_ms then
        message = message .. "TTFT: " .. ansi.underline(self.time_to_first_token_ms .. " ms") .. " "
    end
    if self.rag_duration_ms then
        message = message .. "RAG: " .. ansi.underline(self.rag_duration_ms .. " ms") .. " "
    end
    if self.completion_duration_ms then
        message = message .. "COMPLETION: " .. ansi.underline(self.completion_duration_ms .. " ms") .. " "
    end
    if self.tokens_this_turn > 0 and self.completion_duration_ms then
        local tok_sec = self:tokens_per_second()
        message = message .. ansi.underline(string.format("%.0f tok/s", tok_sec))
    end
    log:info(message)
    return message
end

---@class AgentPerformance
---@field session_start_time_ns integer
---@field turn_count number
---@field turns AgentTurnPerformance[]
---@field total_duration_ms? number
local AgentPerformance = {}
AgentPerformance.__index = AgentPerformance

function AgentPerformance:new()
    self.session_start_time_ns = get_time_in_ns()
    self.turn_count = 0
    self.turns = {}
    self.total_duration_ms = nil
    return self
end

--- Creates a new turn and returns it. Call this before each assistant response.
---@return AgentTurnPerformance
function AgentPerformance:start_turn()
    self.turn_count = self.turn_count + 1
    local turn_perf = AgentTurnPerformance:new(self.turn_count)
    table.insert(self.turns, turn_perf)
    return turn_perf
end

--- Called when the entire agent session completes (accept or cancel)
function AgentPerformance:overall_done()
    if self.total_duration_ms ~= nil then
        error("overall_done called a second time, aborting...")
    end
    self.total_duration_ms = get_elapsed_time_in_rounded_ms(self.session_start_time_ns)

    local message = "AgentSessionPerformance - "
    message = message .. "TURNS: " .. ansi.underline(tostring(self.turn_count)) .. " "
    if self.total_duration_ms then
        message = message .. "TOTAL: " .. ansi.underline(self.total_duration_ms .. " ms") .. " "
    end

    local total_tokens = 0
    for _, turn in ipairs(self.turns) do
        total_tokens = total_tokens + turn.tokens_this_turn
    end
    if total_tokens > 0 then
        local overall_tok_sec = total_tokens / (self.total_duration_ms / 1000)
        message = message .. ansi.underline(string.format("%.0f tok/s", overall_tok_sec))
    end

    log:info(message)

    -- Log per-turn summaries
    for _, turn in ipairs(self.turns) do
        turn:log_summary()
    end

    return message
end

--- Computes overall tokens_per_second across all turns (excluding RAG time from each turn)
---@return number|nil
function AgentPerformance:overall_tokens_per_second()
    if self.total_duration_ms == nil or self.total_duration_ms <= 0 then
        return nil
    end

    local total_tokens = 0
    local total_completion_time_ms = 0

    for _, turn in ipairs(self.turns) do
        total_tokens = total_tokens + turn.tokens_this_turn
        if turn.completion_duration_ms ~= nil and turn.completion_duration_ms > 0 then
            local completion_seconds = turn.completion_duration_ms / 1000
            if turn.rag_duration_ms ~= nil and turn.rag_duration_ms > 0 then
                completion_seconds = completion_seconds - (turn.rag_duration_ms / 1000)
            end
            if completion_seconds > 0 then
                total_completion_time_ms = total_completion_time_ms + (completion_seconds * 1000)
            end
        end
    end

    if total_completion_time_ms <= 0 then
        return 0
    end

    return total_tokens / (total_completion_time_ms / 1000)
end

return AgentPerformance
