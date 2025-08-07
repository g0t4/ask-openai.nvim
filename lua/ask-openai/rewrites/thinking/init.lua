local log = require('ask-openai.logs.logger').predictions()

local M = {
    dots = require("ask-openai.rewrites.thinking.dots"),
}

function M.set_thinking_tag_and_patterns(thinking_tag)
    M.thinking_tag = thinking_tag
end

M.set_thinking_tag_and_patterns("think")


---@enum ThinkingStatus
M.ThinkingStatus = {
    NoThinkingTags = 1,
    Thinking = 2,
    DoneThinking = 3,
    [1] = "NoThinkingTags",
    [2] = "Thinking",
    [3] = "DoneThinking",
}

---@param lines string[]
---@return string[] stripped_lines, ThinkingStatus status
function M.strip_thinking_tags(lines)
    local text = table.concat(lines, "\n")
    -- local open_start, open_end = text:find("^%s*<" .. M.thinking_tag .. ">") -- <think> approach
    local open_start, open_end = text:find("^<|channel|>analysis<|message|>")
    if open_start == nil then
        -- TODO! REMOVE ONCE SSE FIXED
        open_start, open_end = text:find("^analysis<|message|>")
    end
    -- log:trace("combined_text", text)
    if not open_start then
        return lines, M.ThinkingStatus.NoThinkingTags
    end
    -- local close_start, close_end = text:find("</" .. M.thinking_tag .. ">", open_end + 1) -- </think>
    local close_start, close_end = text:find("<|start|>assistant<|channel|>final<|message|>", open_end + 1)
    if not close_start then
        return lines, M.ThinkingStatus.Thinking
    end
    local stripped_text = text:sub(close_end + 1)
    return vim.split(stripped_text, "\n"), M.ThinkingStatus.DoneThinking
end

return M
