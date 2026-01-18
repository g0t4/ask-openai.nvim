local log = require("ask-openai.logs.logger").predictions()
local HLGroups = require("ask-openai.hlgroups")
local safely = require("ask-openai.helpers.safely")

local M = {}

function try_decode_json_string(json_str, message)
    if message:is_still_streaming() then
        return json_str
    end

    local ok, decoded = safely.decode_json(json_str)
    if ok and type(decoded) == "table" then
        return vim.inspect(decoded, { newline = "", indent = "  " })
    end
    return json_str
end

---@param content string
---@param language? string
---@return string
local function code(content, language)
    local lang_prefix = language and #language > 0 and language or ""
    return "```" .. lang_prefix .. "\n" .. content .. "\n```"
end

---@param args string
---@param message RxAccumulatedMessage
---@return string text -- note, not lines
local function handle_apply_patch_args(args, message)
    if message:is_done_streaming() then
        -- FYI this is the only time to log failures, when done streaming:
        local ok, decoded = safely.decode_json(args)
        if ok and type(decoded) == "table" and decoded.patch then
            return code(decoded.patch, "diff")
        end
        -- * fallback is to show unparsed, final args
        -- also add a warning that will show in the chat window
        return args .. "\n\nFailed to decode as JSON"
    end

    local json_prefix = args:match('^{%s*"patch"%s*:%s*"')
    if not json_prefix then
        return args
    end

    -- * try to complete the JSON string and decode it
    -- assumption is, if final '"}' is present then it would be done streaming (sans maybe one delta?)
    local try_finish_args = args .. '"}'
    local ok, decoded = safely.decode_json_ignore_failure(try_finish_args)
    if ok and type(decoded) == "table" and decoded.patch then
        return code(decoded.patch, "diff")
    else
        -- * fallback => try parse as-is
        local ok, decoded = safely.decode_json_ignore_failure(args)
        if ok and type(decoded) == "table" and decoded.patch then
            return code(decoded.patch, "diff")
        end
        -- * fallback => return unparsed
        return args
    end
end

---@type ToolCallFormatter
function M.format(lines, tool_call, message)
    -- if message:is_still_streaming() then
    --     -- TODO?
    --     -- TODO OR message:get_lifecycle_step() == RxAccumulatedMessage.RX_LIFECYCLE.FINISHED
    --     return
    -- end

    local func_name = tool_call["function"].name
    local tool_header = func_name or ""

    local hl_group = HLGroups.TOOL_SUCCESS
    if tool_call.call_output then
        if tool_call.call_output.result.isError then
            tool_header = "❌ " .. tool_header
            hl_group = HLGroups.TOOL_FAILED
        else
            tool_header = "✅ " .. tool_header
        end
    end
    lines:append_styled_text(tool_header, hl_group)

    -- * tool args
    local args = tool_call["function"].arguments
    if args then
        if func_name == "apply_patch" then
            lines:append_text(handle_apply_patch_args(args, message))
        else
            lines:append_text(try_decode_json_string(args, message))
        end
    end
    -- PRN mark outputs somehow? or just dump them? (I hate to waste space)

    -- * tool result
    if not tool_call:is_done() then
        -- PRN for slow tools, use thinking dots ... as calling dots!
        lines:append_unexpected_line("Tool call in progress...")
        return
    end

    -- TODO add failure recovery to building messages for logs... do not kill things b/c a formatter failed!
    --  allow agent to continue even if formatters are FUUUUU

    local is_mcp_like_output = tool_call.call_output and tool_call.call_output:is_mcp()
    if is_mcp_like_output then
        ---@type MCPToolResultContent[]
        local content = tool_call.call_output.result.content

        local multiple_outputs = #content > 1
        for _, output in ipairs(content) do
            local name = output.name
            local text = tostring(output.text or "")
            if not text then
                -- PRN log and/or skip?
                if name then
                    lines:append_text(name)
                else
                    lines:append_text("[ empty text ]")
                end
            elseif name == "STDOUT" then
                if text then
                    lines:append_STDOUT(text)
                end
            else
                -- GENERIC output type
                if (name == nil or name == "") and multiple_outputs then
                    name = "[NO NAME] and multiple outputs" -- heads up for now so I can identify scenarios/tools, can remove this later
                end
                if output.type == "text" then
                    local is_multi_line = text:match("\n")
                    if is_multi_line then
                        if name then
                            lines:append_text(name .. ":")
                        end
                        lines:append_text(text)
                    else
                        -- single line
                        if name then
                            lines:append_text(name .. ": " .. text)
                        else
                            lines:append_text(text)
                        end
                    end
                else
                    lines:append_unexpected_text("  UNEXPECTED type: \n" .. vim.inspect(output))
                end
            end
        end
    else
        -- TODO NON-MCP tool responses
        --  i.e. in-process tools: rag_query, apply_patch
    end
end

return M
