local M = {}

---@enum FINISH_REASON
M.FINISH_REASON = {
    LENGTH = "length",
    STOP = "stop",
    TOOL_CALLS = "tool_calls",
    -- observed finish_reason values: "tool_calls", "stop", "length", null (not string, a literal null JSON value)
    -- vim.NIL (still streaming) => b/c of JSON value of null (not string, but literal null in the JSON)

    -- FYI find finish_reason observed values:
    --   grep --no-filename -o '"finish_reason":[^,}]*' **/* 2>/dev/null | sort | uniq
    -- "finish_reason":"length"
    -- "finish_reason":"stop"
    -- "finish_reason":"tool_calls"
    -- "finish_reason":null
}

return M
