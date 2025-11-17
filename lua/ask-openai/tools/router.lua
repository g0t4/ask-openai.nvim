local mcp = require("ask-openai.tools.mcp")
local inprocess = require("ask-openai.tools.inprocess")

local M = {}

function M.openai_tools()
    local tools = {}
    for _, mcp_tool in pairs(mcp.tools_available) do
        table.insert(tools, openai_tool(mcp_tool))
    end
    for _, inprocess_tool in pairs(inprocess.tools_available) do
        table.insert(tools, inprocess_tool)
    end
    return tools
end

---@alias ToolCallDoneCallback fun(call_output: table)

---@param tool_call table
---@param callback ToolCallDoneCallback
function M.send_tool_call_router(tool_call, callback)
    local tool_name = tool_call["function"].name

    if mcp.handles_tool(tool_name) then
        mcp.send_tool_call(tool_call, callback)
        return
    end

    if inprocess.handles_tool(tool_name) then
        inprocess.send_tool_call(tool_call, callback)
        return
    end

    -- for now it's fine to just fail here with an error
    error("tool not found: " .. tool_name)
end

return M
