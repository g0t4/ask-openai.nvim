local log = require("ask-openai.logs.logger").predictions()
local plumbing = require("ask-openai.tools.plumbing")

local M = {}

--- OpenAI tool definition for executing arbitrary Lua code within the Neovim process.
---@type OpenAITool
M.ToolDefinition = {
    ["function"] = {
        description = "Execute arbitrary Lua code in the Neovim process. Useful for calling vim API functions like vim.notify or vim.cmd.",
        name = "run_lua",
        parameters = {
            type = "object",
            properties = {
                code = {
                    type = "string",
                    description = "Lua code to execute. Should be a valid Lua chunk."
                },
            },
            required = { "code" },
        },
    },
    type = "function",
}

--- Execute the provided Lua code safely using pcall.
---@param parsed_args table Parsed arguments from the tool call.
---@param callback ToolCallDoneCallback Callback to return the tool result.
function M.call(parsed_args, callback)
    local code = parsed_args.code
    if type(code) ~= "string" or code:match("^%s*$") then
        callback(plumbing.create_tool_call_output_for_error_message("'code' argument must be a non‑empty string"))
        return
    end

    local fn, load_err = loadstring(code)
    if not fn then
        callback(plumbing.create_tool_call_output_for_error_message("Failed to load Lua code: " .. tostring(load_err)))
        return
    end

    -- TODO need async design with callback to trigger when there is a result... i.e. if ask user for input, need to get answer... and wait for that before the tool finishes up... right now it's sync only
    --
    local ok, result = pcall(fn)
    if not ok then
        callback(plumbing.create_tool_call_output_for_error_message("Error executing Lua code: " .. tostring(result)))
        return
    end

    -- Convert the result to a string for returning to the model.
    local output = result
    if output == nil then
        output = ""
    else
        output = tostring(output)
    end
    callback(plumbing.create_tool_call_output_for_success({ plumbing.text_content(output) }))
end

return M
