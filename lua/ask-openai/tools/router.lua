local mcp = require("ask-openai.tools.mcp")
local inprocess = require("ask-openai.tools.inprocess")
local plumbing = require("ask-openai.tools.plumbing")
local apply_patch_tool = require("ask-openai.tools.inproc.apply_patch")

local M = {}

function M.openai_tools()
    local tools = {}
    local system_message_instructions = {}
    for _, mcp_tool in pairs(mcp.tools_available) do
        table.insert(tools, openai_tool(mcp_tool))
    end
    for _, inprocess_tool in pairs(inprocess.tools_available) do
        table.insert(tools, inprocess_tool)

        -- hack to inject instructions, will revisit later
        if inprocess_tool["function"].name == "apply_patch" then
            -- TODO move this down into inprocess module to aggregate?
            table.insert(system_message_instructions, apply_patch_tool.get_system_message_instructions())
        end
    end
    return tools, system_message_instructions
end

---@alias ToolCallDoneCallback fun(call_output: table|MCPToolCallOutputResult|MCPToolCallOutputError)

---@param tool_call table
---@param callback ToolCallDoneCallback
function M.send_tool_call_router(tool_call, callback)
    local tool_name = tool_call["function"].name
    -- local tool_name = "no_way" -- FYI test tool call failure plumbing (callbacks)

    if mcp.handles_tool(tool_name) then
        mcp.send_tool_call(tool_call, callback)
        return
    end

    if inprocess.handles_tool(tool_name) then
        inprocess.send_tool_call(tool_call, callback)
        return
    end

    callback(plumbing.create_tool_call_output_for_error_message("Invalid tool name: " .. tool_name))
end

return M
