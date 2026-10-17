local log = require("devtools.logs.logger").universal()
local HLGroups = require("ask-openai.hlgroups")
local safely = require("ask-openai.helpers.safely")
local base = require("ask-openai.agents.viewer.formatters.base")

local M = {}

--- Wrap content in a fenced code block for markdown rendering.
---
---@param content string
---@param language? string
---@return string
local function fenced_code(content, language)
    local lang_prefix = (language and #language > 0) and language or ""
    return "```" .. lang_prefix .. "\n" .. content .. "\n```"
end

--- Append the run_xonsh arguments to the lines builder.
---
--- While streaming, show the raw (possibly partial) JSON args. Once streaming is
--- done, decode the JSON and display the `code` arg as a fenced code block, plus
--- any remaining args (e.g. cwd, timeout_seconds) as key: value pairs.
---
---@param lines LinesBuilder
---@param args_json string
---@param message RxAccumulatedMessage
local function append_args(lines, args_json, message)
    if message:is_still_streaming() then
        lines:append_text(args_json)
        return
    end

    local ok, decoded = safely.decode_json(args_json)
    if not ok or type(decoded) ~= "table" then
        log:error("failed to decode run_xonsh arguments", args_json)
        lines:append_text(args_json)
        return
    end

    -- * show the code arg in a readable fenced code block
    local code_arg = decoded.code
    if code_arg then
        decoded.code = nil
        lines:append_text(fenced_code(code_arg, "python"))
    end

    -- * show the remaining args (cwd, timeout_seconds, ...)
    for key, value in pairs(decoded) do
        lines:append_text(key .. ": " .. vim.inspect(value))
    end
end

--- Append the MCP-style tool result (STDOUT / STDERR / generic text) to the lines.
---
---@param lines LinesBuilder
---@param tool_call ToolCall
local function append_result(lines, tool_call)
    local output = tool_call.call_output
    if not output or not output.result or not output.result.content then
        return
    end

    ---@type MCP_ContentBlock[]
    local content = output.result.content
    for _, block in ipairs(content) do
        local name = block.name
        local text = tostring(block.text or "")

        if name == "STDOUT" or name == "STDERR" then
            if text and #text > 0 then
                lines:append_text_fold_if_long(name, text)
            end
        elseif block.type == "text" then
            if name and #name > 0 then
                lines:append_text(name .. ": " .. text)
            else
                lines:append_text(text)
            end
        else
            lines:append_unexpected_text("  UNEXPECTED type: \n" .. vim.inspect(block))
        end
    end
end

---@type ToolCallFormatter
function M.format(lines, tool_call, message)
    base.add_generic_header(lines, tool_call)

    -- * tool args
    local func = tool_call["function"]
    local args = func.arguments
    if args then
        append_args(lines, args, message)
    end

    -- * progress messages (shown when tool is still running)
    local is_tool_done = tool_call:is_done()
    base.render_progress(lines, tool_call, is_tool_done)

    if not is_tool_done then
        return
    end

    -- * tool result
    append_result(lines, tool_call)
end

return M
