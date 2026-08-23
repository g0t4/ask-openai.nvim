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

--- Cooperative cancellation for long-running Lua.
--- The cancel fn sets a flag that the running code can poll via `vim.g.__ask_cancelled`.
--- Cooperative sleeps look like:
---   vim.wait(60000, function() return vim.g.__ask_cancelled end, 100)
--- NOTE: a plain blocking sleep (e.g. `vim.wait(60000)` w/o a cancel-checking callback)
---       still blocks the event loop so it can't be interrupted mid-flight; the request
---       is still marked cancelled so the agent stops and ignores its (late) result.
---@param parsed_args table Parsed arguments from the tool call.
---@param callback ToolCallDoneCallback Callback to return the tool result.
---@return fun() cancel function (cooperative)
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

    local cancelled = false

    -- * expose a cooperative cancel flag to the running code (so it can poll & abort)
    vim.g.__ask_cancelled = false

    local function cancel_fn()
        if cancelled then
            return
        end
        cancelled = true
        vim.g.__ask_cancelled = true
    end

    -- * dispatch execution async so we can hand back the cancel fn immediately
    vim.schedule(function()
        if cancelled then
            callback(plumbing.create_tool_call_output_for_error_message("run_in_neovim cancelled before execution"))
            return
        end

        local ok, result = pcall(loaded_lua_fn)
        if cancelled then
            -- * request was aborted; report it (frontend ignores the result anyway via request.cancelled)
            callback(plumbing.create_tool_call_output_for_error_message("run_in_neovim cancelled"))
            return
        end
        vim.g.__ask_cancelled = nil

        if not ok then
            callback(plumbing.create_tool_call_output_for_error_message("Error executing Lua code: " .. tostring(result)))
            return
        end

        -- vim.inspect else it will be tostring'd and tables will show as 0x14a2870 and that's not so helpful to the model!
        --  also the output viewer should be able to rely on text and not a lua object
        local output = vim.inspect(result)
        callback(plumbing.create_tool_call_output_for_success({ plumbing.text_content(output, "RESULT") }))
    end)

    return cancel_fn
end

return M
