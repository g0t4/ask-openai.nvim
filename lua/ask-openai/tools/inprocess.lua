local apply_patch_tool = require("ask-openai.tools.inproc.apply_patch")
local plumbing = require("ask-openai.tools.plumbing")
local semantic_grep_tool = require("ask-openai.tools.inproc.semantic_grep")
local run_in_neovim_tool = require("ask-openai.tools.inproc.run_in_neovim")
local open_image_tool = require("ask-openai.tools.inproc.open_image")

local M = {}

---@type OpenAITool[]
M.tools_available = {
    semantic_grep_tool.ToolDefinition,
    -- TODO setup so tools available can be model dependent (i.e. gptoss gets apply_patch)
    apply_patch_tool.ToolDefinition,
    run_in_neovim_tool.ToolDefinition,
    open_image_tool.ToolDefinition,
}

---@param tool_name string
---@return boolean
function M.handles_tool(tool_name)
    for _, inprocess_tool in ipairs(M.tools_available) do
        local name = inprocess_tool["function"].name
        if name == tool_name then
            return true
        end
    end
    return false
end

---@alias InProcessToolCall
---| fun(parsed_args: table, callback: ToolCallDoneCallback): fun() cancel

---@param tool_call table
---@param callback ToolCallDoneCallback
---@return fun() cancel function
function M.send_tool_call(tool_call, callback)
    local args = tool_call["function"].arguments
    local parsed_args = vim.json.decode(args)

    local name = tool_call["function"].name
    if name == "semantic_grep" then
        return semantic_grep_tool.call(parsed_args, callback)
    end
    if name == "apply_patch" then
        return apply_patch_tool.call(parsed_args, callback)
    end
    if name == "open_image" then
        return open_image_tool.call(parsed_args, callback)
    end
    if name == "run_in_neovim" then
        return run_in_neovim_tool.call(parsed_args, callback)
    end
    callback(plumbing.create_tool_call_output_for_error_message("Invalid in-process tool name: " .. name))
end

return M
