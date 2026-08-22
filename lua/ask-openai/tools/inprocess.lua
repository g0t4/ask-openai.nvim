local apply_patch_tool = require("ask-openai.tools.inproc.apply_patch")
local plumbing = require("ask-openai.tools.plumbing")
local semantic_grep_tool = require("ask-openai.tools.inproc.semantic_grep")
local run_in_neovim_tool = require("ask-openai.tools.inproc.run_in_neovim")

local M = {}

-- no-op cancel for tools that have no obvious cooperative-cancel hook yet
local function empty_cancel() end

---@type OpenAITool[]
M.tools_available = {
    semantic_grep = semantic_grep_tool.ToolDefinition,
    -- TODO setup so tools available can be model dependent (i.e. gptoss gets apply_patch)
    -- apply_patch = apply_patch_tool.ToolDefinition,
    -- run_in_neovim = run_in_neovim_tool.ToolDefinition,
    --   TODO setup slash commands that can trigger tools like run_in_neovim
}


---@param tool_name string
---@return boolean
function M.handles_tool(tool_name)
    local tool = M.tools_available[tool_name]
    return tool ~= nil
end

---@param tool_call table
---@param callback ToolCallDoneCallback
---@return fun() cancel function (no-op for synchronous/fast tools without an obvious cancel)
function M.send_tool_call(tool_call, callback)
    local args = tool_call["function"].arguments
    local parsed_args = vim.json.decode(args)

    local name = tool_call["function"].name
    if name == "semantic_grep" then
        -- semantic_grep exposes its LSP-request cancel fn directly
        return semantic_grep_tool.call(parsed_args, callback) or empty_cancel
    elseif name == "apply_patch" then
        apply_patch_tool.call(parsed_args, callback)
    elseif name == "run_in_neovim" then
        run_in_neovim_tool.call(parsed_args, callback)
    else
        callback(plumbing.create_tool_call_output_for_error_message("Invalid in-process tool name: " .. name))
    end
    -- synchronous/fast tools: nothing meaningful to cancel yet
    return empty_cancel
end

return M
