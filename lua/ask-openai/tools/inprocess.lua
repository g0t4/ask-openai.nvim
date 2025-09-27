local M = {}

-- In-process tools would be added here
-- For now, we'll just have the basic structure

M.tools_available = {
    hello_new_tool = {
        name = "hello_new_tool",
        description = "A simple tool that prints a greeting message",
        inputSchema = {
            type = "object",
            properties = {},
            required = {}
        }
    }
}

---@param tool_name string
---@return boolean
function M.handles_tool(tool_name)
    local tool = M.tools_available[tool_name]
    return tool ~= nil
end

---@param tool_call table
---@param callback fun(response: table)
function M.send_tool_call(tool_call, callback)
    -- Execute the hello new tool function
    local name = tool_call["function"].name
    
    if name == "hello_new_tool" then
        local response = {
            result = "Hello from the new in-process tool!"
        }
        callback(response)
        return
    end
    
    error("in-process tool not implemented yet: " .. name)
end

return M
