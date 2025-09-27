local M = {}

-- In-process tools would be added here
-- For now, we'll just have the basic structure

M.tools_available = {}

---@param tool_name string
---@return boolean
function M.handles_tool(tool_name)
    local tool = M.tools_available[tool_name]
    return tool ~= nil
end

---@param tool_call table
---@param callback fun(response: table)
function M.send_tool_call(tool_call, callback)
    -- Placeholder for in-process tool execution
    -- This will be implemented when actual tools are added
    local name = tool_call["function"].name
    error("in-process tool not implemented yet: " .. name)
end

return M
