local mcp = require("ask-openai.tools.mcp")

local M = {}

---@param tool_call table
---@param callback fun(response: table)
function M.send_tool_call_router(tool_call, callback)
    local tool_name = tool_call["function"].name
    local handles = mcp.handles_tool(tool_name)
    if handles then
        mcp.send_tool_call(tool_call, callback)
        return
    end

    -- for now it's fine to just fail here with an error
    error("tool not found: " .. tool_name)
end

return M
