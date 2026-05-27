local mcp = require("ask-openai.tools.mcp")
local inprocess = require("ask-openai.tools.inprocess")
local plumbing = require("ask-openai.tools.plumbing")
local apply_patch_tool = require("ask-openai.tools.inproc.apply_patch")
local client = require("ask-openai.rag.client.client")
local log = require("ask-openai.logs.logger").predictions()

local M = {}

---@param coordinator_only boolean # primary agent will not have any tool calls beyond spinning up a subagent!
function M.openai_tools(coordinator_only)
    -- * inject system message instructions based on available tools
    local function _openai_tools(coordinator_only)
        ---@type OpenAITool[]
        local tools = {}
        local system_instructs = {}

        if coordinator_only then
            log:info("COORDINATOR_ONLY")
            -- * coordinator only gets the "agents" tool (for spawning subagents)
            local delegate_tool = mcp.tools_available["delegate"]
            if delegate_tool then
                table.insert(tools, mcp.openai_tool(delegate_tool))
            end
            return tools, system_instructs
        end

        for name, mcp_tool in pairs(mcp.tools_available) do
            table.insert(tools, mcp.openai_tool(mcp_tool))
            local tool_instructs = mcp.get_system_message_instructions(name)
            if tool_instructs then
                table.insert(system_instructs, tool_instructs)
            end
        end

        for _, inprocess_tool in pairs(inprocess.tools_available) do
            -- PRN push this into inprocess module like mcp/init.lua above?

            if inprocess_tool["function"].name == "semantic_grep" then
                -- somewhat strange but neovim invocations are rooted in the current buffer,
                -- so I have to use that to dictate some tool availability even though agent‑like
                -- requests are buffer independent... since my LS client is tied to a buffer in
                -- neovim, gotta roll with it! NBD TBH
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
    local tools, system_instructs = _openai_tools(coordinator_only)
    local names = vim.iter(tools)
        :map(function(tool) return tool["function"].name end)
        :join(', ')
    log:info("tools:", names)
    return tools, system_instructs
end

---@alias ToolCallDoneCallback fun(call_output: table|MCPToolCallOutputResult|MCPToolCallOutputError)
---@alias ToolCallOnProgress fun(progress: table)

---@param tool_call table
---@param callback ToolCallDoneCallback
---@param on_progress? ToolCallOnProgress
function M.send_tool_call_router(tool_call, callback, on_progress)
    local tool_name = tool_call["function"].name

    local function safe_call(fn)
        -- treat as tool call failure, that way model can choose how to recover... vs just killing your tool runner :)
        local ok, err = pcall(fn)
        if not ok then
            callback(plumbing.create_tool_call_output_for_error_message(err))
        end
    end

    local function safe_on_progress(...)
        -- right now, all mcp tool calls flow through here
        -- so this feels like a good spot to wrap `on_progress`
        -- plus I am doing that with `callback` here too
        --
        -- also by setting this up here, in MCP land I can require on_progress for all tool calls and this will just silently ignore progress if a tool doesn't want to use it
        if not on_progress then
            log:warn(string.format("Tool [%s] progress received but there's no on_progress registered: %s", tool_name, vim.inspect({ ... })))
            return
        end
        local ok, err = pcall(on_progress, ...)
        if not ok then
            log:error(string.format("Tool [%s] on_progress callback error: %s", tool_name, err))
        end
    end

    if mcp.handles_tool(tool_name) then
        safe_call(function() mcp.send_tool_call(tool_call, callback, safe_on_progress) end)
        return
    end

    if inprocess.handles_tool(tool_name) then
        safe_call(function() inprocess.send_tool_call(tool_call, callback) end)
        return
    end

    callback(plumbing.create_tool_call_output_for_error_message("Invalid tool name: " .. tool_name))
end

return M
