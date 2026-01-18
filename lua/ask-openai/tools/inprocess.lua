local apply_patch_tool = require("ask-openai.tools.inproc.apply_patch")
local plumbing = require("ask-openai.tools.plumbing")
local semantic_grep_tool = require("ask-openai.tools.inproc.semantic_grep")

local M = {}

---@type OpenAITool[]
M.tools_available = {
    semantic_grep = semantic_grep_tool.ToolDefinition,
    apply_patch = apply_patch_tool.ToolDefinition,
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
        semantic_grep_tool.call(parsed_args, callback)
    elseif name == "apply_patch" then
        apply_patch_tool.call(parsed_args, callback)
    else
        callback(plumbing.create_tool_call_output_for_error_message("Invalid in-process tool name: " .. name))
    end
end

return M
