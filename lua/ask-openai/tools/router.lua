local mcp = require("ask-openai.tools.mcp")
local inprocess = require("ask-openai.tools.inprocess")
local plumbing = require("ask-openai.tools.plumbing")
local apply_patch_tool = require("ask-openai.tools.inproc.apply_patch")
local client = require("ask-openai.rag.client.client")

local M = {}

function M.openai_tools()
    local tools = {}

    -- * inject system message instructions based on available tools
    local system_instructs = {}
    for name, mcp_tool in pairs(mcp.tools_available) do
        table.insert(tools, openai_tool(mcp_tool))
        local tool_instructs = mcp.get_system_message_instructions(name)
        if tool_instructs then
            table.insert(system_instructs, tool_instructs)
        end
    end
    for _, inprocess_tool in pairs(inprocess.tools_available) do
        -- PRN push this into inprocess module like mcp/init.lua above?

        if inprocess_tool["function"].name == "semantic_grep" then
            -- somewhat strange but neovim invocations are rooted in the current buffer, so I have to use that to dictate some tool availability even though agent like requests are buffer independent... since my LS client is tied to a buffer in neovim, gotta roll with it! NBD TBH
            if client.is_lsp_client_available() then
                table.insert(tools, inprocess_tool)
            end
        else
            table.insert(tools, inprocess_tool)
            if inprocess_tool["function"].name == "apply_patch" then
                table.insert(system_instructs, apply_patch_tool.get_system_message_instructions())
            end
        end
    end
    return tools, system_instructs
end

---@alias ToolCallDoneCallback fun(call_output: table|MCPToolCallOutputResult|MCPToolCallOutputError)

---@param tool_call table
---@param callback ToolCallDoneCallback
function M.send_tool_call_router(tool_call, callback)
    local tool_name = tool_call["function"].name
    -- local tool_name = "no_way" -- FYI test tool call failure plumbing (callbacks)

    local function safe_call(fn)
        -- treat as tool call failure, that way model can choose how to recover... vs just killing your tool runner :)
        local ok, err = pcall(fn)
        if not ok then
            callback(plumbing.create_tool_call_output_for_error_message(err))
        end
    end

    if mcp.handles_tool(tool_name) then
        safe_call(function() mcp.send_tool_call(tool_call, callback) end)
        return
    end

    if inprocess.handles_tool(tool_name) then
        safe_call(function() inprocess.send_tool_call(tool_call, callback) end)
        return
    end

    callback(plumbing.create_tool_call_output_for_error_message("Invalid tool name: " .. tool_name))
end

return M
