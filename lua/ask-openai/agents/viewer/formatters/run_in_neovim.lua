local HLGroups = require("ask-openai.hlgroups")
local safely = require("ask-openai.helpers.safely")
local base = require("ask-openai.agents.viewer.formatters.base")

local M = {}

---@type ToolCallFormatter
function M.format(lines, tool_call, message)

    local func = tool_call["function"]
    local name = func.name or "run_in_neovim"
    local hl_group = HLGroups.TOOL_SUCCESS
    if tool_call.call_output then
        if tool_call.call_output.result.isError then
            name = "❌ " .. name
            hl_group = HLGroups.TOOL_FAILED
        else
            name = "✅ " .. name
        end
    end
    lines:append_styled_text(name, hl_group)

    local args = func.arguments
    if args then
        local ok, decoded = safely.decode_json(args)
        if ok and type(decoded) == "table" and decoded.lua then
            lines:append_text_fold_if_long("LUA", decoded.lua)
        else
            lines:append_text(args)
        end
    end

    -- * progress messages (shown when tool is still running)
    local is_tool_done = tool_call:is_done()
    base.render_progress(lines, tool_call, is_tool_done)

    if not is_tool_done then
        return
    end

    -- currently expression result is the only item in the content list, using an MCP like output though with type/name... ignore that and just get the value to display
    local first_content = tool_call.call_output.result.content[1]
    lines:append_text(first_content.text)
end

return M
