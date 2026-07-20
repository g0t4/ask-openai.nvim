local log = require("devtools.logs.logger").universal()
local perf = require("devtools.performance")

--- Registry for tracking performance objects across all frontends
--- and determining the most recently used frontend
local M = {}

--- All registered performance objects
---@type table<string, any>[]
M.all_performances = {}

--- The type of the most recently used frontend
---@type string|nil
M.last_used_type = nil

--- The most recent performance object by type
---@type table<string, any>
M.latest_by_type = {}

--- Register a performance object with a type identifier
--- @param type string - The frontend type (e.g., "fim", "rewrite", "agents")
--- @param perf any - The performance object to register
function M.register(type, perf)
    if not type or not perf then
        error("register requires type and perf arguments")
    end

    -- Add type field to performance object for identification
    perf.type = type

    -- Store in all performances array
    table.insert(M.all_performances, perf)

    -- Update latest by type (most recent wins)
    M.latest_by_type[type] = perf

    -- Update last used type
    M.last_used_type = type

    log:trace("PerformanceRegistry registered type=" .. type)
end

--- Get the most recent performance object for a specific type
--- @param type string
---@return any|nil
function M.get_latest(type)
    return M.latest_by_type[type]
end

--- Get the most recently used performance object (across all types)
---@return any|nil
function M.get_most_recent()
    if not M.last_used_type then
        return nil
    end
    return M.latest_by_type[M.last_used_type]
end

--- Format performance stats for display in lualine
--- @param perf any - The performance object
---@return string
function M.format_stats_for_lualine(perf)
    if not perf then
        return ""
    end

    local parts = {}

    -- Get tokens per second if available
    local tok_sec = nil
    if type(perf.tokens_per_second) == "function" then
        -- For RewritePerformance and AgentTurnPerformance
        if perf.num_deltas_content ~= nil then
            tok_sec = perf:tokens_per_second(perf.num_deltas_content, perf.num_deltas_reasoning or 0)
        elseif perf.tokens_this_turn ~= nil then
            tok_sec = perf:tokens_per_second()
        end
    elseif perf.tokens_per_second ~= nil then
        -- For AgentPerformance (overall)
        tok_sec = perf:overall_tokens_per_second()
    end

    if tok_sec and tok_sec > 0 then
        table.insert(parts, string.format("%.0f tok/s", tok_sec))
    end

    -- Add RAG time if available
    if perf.rag_duration_ms ~= nil and perf.rag_duration_ms > 0 then
        table.insert(parts, string.format("RAG: %.0fms", perf.rag_duration_ms))
    end

    -- Add TTFT if available
    if perf.time_to_first_token_ms ~= nil and perf.time_to_first_token_ms > 0 then
        table.insert(parts, string.format("TTFT: %.0fms", perf.time_to_first_token_ms))
    end

    -- Add total time if available
    if perf.total_duration_ms ~= nil and perf.total_duration_ms > 0 then
        table.insert(parts, string.format("%.0fms", perf.total_duration_ms))
    end

    return table.concat(parts, " ")
end

--- Format the most recent stats for lualine display
---@return string
function M.get_recent_stats()
    local perf = M.get_most_recent()
    if not perf then
        return ""
    end

    local type_label = perf.type or "unknown"
    local formatted = M.format_stats_for_lualine(perf)

    if not formatted or formatted == "" then
        return ""
    end

    -- Return with type prefix for clarity
    return string.format("[%s] %s", type_label, formatted)
end

M.get_time_in_ns = perf.get_time_in_ns

return M
