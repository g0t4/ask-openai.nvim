local log = require("devtools.logs.logger").universal()
local plumbing = require("ask-openai.tools.plumbing")

local M = {}

--- OpenAI tool definition for executing arbitrary Lua code within the Neovim process.
---@type OpenAITool
M.ToolDefinition = {
    ["function"] = {
        description = "Execute Lua code in the current Neovim process (that hosts your agent). For example, call vim.cmd()",
        name = "run_in_neovim",
        parameters = {
            type = "object",
            properties = {
                lua = {
                    type = "string",
                    description = "Lua code to execute. Should be a valid Lua chunk."
                },
            },
            required = { "lua" },
        },
    },
    type = "function",
}

--- Execute the provided Lua code safely using pcall.
---@param parsed_args table Parsed arguments from the tool call.
---@param callback ToolCallDoneCallback Callback to return the tool result.
function M.call(parsed_args, callback)
    local lua_code = parsed_args.lua
    if type(lua_code) ~= "string" or lua_code:match("^%s*$") then
        callback(plumbing.create_tool_call_output_for_error_message("'lua' argument must be a non‑empty string"))
        return
    end

    local loaded_lua_fn, load_err = loadstring(lua_code)
    if not loaded_lua_fn then
        callback(plumbing.create_tool_call_output_for_error_message("Failed to load Lua code: " .. tostring(load_err)))
        return
    end

    -- TODO need async design with callback to trigger when there is a result... i.e. if ask user for input, need to get answer... and wait for that before the tool finishes up... right now it's sync only
    --
    local ok, result = pcall(loaded_lua_fn)
    if not ok then
        callback(plumbing.create_tool_call_output_for_error_message("Error executing Lua code: " .. tostring(result)))
        return
    end

    -- vim.inspect else it will be tostring'd and tables will show as 0x14a2870 and that's not so helpful to the model!
    --  also the output viewer should be able to rely on text and not a lua object
    local output = vim.inspect(result)
    callback(plumbing.create_tool_call_output_for_success({ plumbing.text_content(output, "RESULT") }))
end

return M
