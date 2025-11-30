local apply_patch_tool = require("ask-openai.tools.inproc.apply_patch")
local plumbing = require("ask-openai.tools.plumbing")
local semantic_grep_tool = require("ask-openai.tools.inproc.semantic_grep")

local M = {}

---@type OpenAITool[]
M.tools_available = {
    semantic_grep = semantic_grep_tool.ToolDefinition
    -- apply_patch = apply_patch_module.ToolDefinition -- TODO
}

---@param tool_name string
---@return boolean
function M.handles_tool(tool_name)
    local tool = M.tools_available[tool_name]
    return tool ~= nil
end

---@param tool_call table
---@param callback ToolCallDoneCallback
function M.send_tool_call(tool_call, callback)
    local args = tool_call["function"].arguments
    local parsed_args = vim.json.decode(args)

    local name = tool_call["function"].name
    if name == "semantic_grep" then
        semantic_grep_tool.semantic_grep(parsed_args, callback)
    elseif name == "apply_patch" then
        M.apply_patch(parsed_args, callback)
        -- TODO try other tools from gptoss repo? (python code runner, browser)
    else
        callback(plumbing.create_tool_call_output_failure("Invalid in-process tool name: " .. name))
    end
end

---@param parsed_args table
---@param callback ToolCallDoneCallback
function M.apply_patch(parsed_args, callback)
    -- GPTOSS has an apply_patch tool it was trained with
    -- instead of bothering with an MCP server, let's just trigger the python script in-process
    -- later I can move this out to another process (MCP server) if that is worthwhile
    callback(plumbing.create_tool_call_output_failure("apply_patch command is not yet connected!!! patience"))
end

return M
