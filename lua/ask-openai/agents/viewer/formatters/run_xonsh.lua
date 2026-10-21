local log = require("devtools.logs.logger").universal()
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

--- Resolve the header text for the tool call.
---
--- While streaming, fall back to the raw tool name. Once streaming is done, if
--- the `code` arg is a single line (no newline), use it as the header/title;
--- otherwise return the plain tool name (the multi-line code is shown as a block).
---
---@param args_json string
---@param message RxAccumulatedMessage
---@return string header
---@return table? decoded_args
local function get_header_text(args_json, message)
    if message:is_still_streaming() then
        return nil, nil
    end

    local ok, decoded = safely.decode_json(args_json)
    if not ok or type(decoded) ~= "table" then
        log:error("failed to decode run_xonsh arguments", args_json)
        return nil, nil
    end

    local code_arg = decoded.code
    if code_arg then
        -- * single-line code => use as the header/title
        if not code_arg:match("\n") then
            decoded.code = nil
            return code_arg, decoded
        end
        -- * multi-line code => shown as a fenced code block (handled by append_args)
    end

    return nil, decoded
end

--- Append the run_xonsh arguments to the lines builder.
---
--- The `code` arg is shown as a fenced code block (multi-line), while any
--- remaining args (e.g. cwd, timeout_seconds) are shown as key: value pairs.
---
---@param lines LinesBuilder
---@param args_json string
---@param decoded_args table?
local function append_args(lines, args_json, decoded_args)
    if decoded_args then
        -- * show the code arg in a readable fenced code block (multi-line only)
        local code_arg = decoded_args.code
        if code_arg then
            lines:append_text(fenced_code(code_arg, "python"))
            decoded_args.code = nil
        end

    -- * show the remaining args (cwd, timeout_seconds, ...)
        for key, value in pairs(decoded_args) do
            lines:append_text(key .. ": " .. vim.inspect(value))
        end
    else
        -- * streaming or decode failure => show raw args
        lines:append_text(args_json)
    end
end

---@type ToolCallFormatter
function M.format(lines, tool_call, message)
    local args_json = tool_call["function"].arguments
    local header, decoded_args = get_header_text(args_json, message)
    base.add_generic_header(lines, tool_call, header)

    -- * tool args
    if args_json then
        append_args(lines, args_json, decoded_args)
    end

    -- * progress messages (shown when tool is still running)
    local is_tool_done = tool_call:is_done()
    base.render_progress(lines, tool_call, is_tool_done)

    if not is_tool_done then
        return
    end

    -- * tool result
    base.render_tool_result(lines, tool_call)
end

return M
