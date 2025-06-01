local M = {
    dots = require("ask-openai.rewrites.thinking.dots"),
}

-- TODO track instances of thinking so I could be running parallel prompts
--   and parallel thinking responses
--   would also clean up code usage, feel more natural most likely

function M.set_thinking_tag_and_patterns(thinking_tag)
    M.thinking_tag = thinking_tag
    -- FYI - == match shortest possible sequence (thus we can find first full closinng tag afterwards while skipping partial tags)
    --    also %s%S helps match everything possible, including newlines
    --    :h lua-patternitem
    M.thinking_open_and_close_tags = "^%s*<" .. thinking_tag .. ">[%s%S]-</" .. thinking_tag .. ">"
    -- PRN add () around all of the thinking tag text so I can extract it to paste a comment on demand

    -- TODO explore detecting and stripping or showing animation when thinking tag isn't closed yet
    M.thinking_open_tag_only = "^%s*<" .. thinking_tag .. ">[^<]*"
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
    -- must only have whitespace before the opening tag
    -- FYI it might actually be easier to just scan for open tag, then first close tag after it... if regex gets yucky
    -- text = text:gsub(M.thinking_open_and_close_tags, "")
    local open_start, open_end = text:find("^%s*<" .. M.thinking_tag .. ">")
    if not open_start then
        return lines, M.ThinkingStatus.NoThinkingTags
    end
    local close_start, close_end = text:find("</" .. M.thinking_tag .. ">", open_end + 1)
    if not close_start then
        -- TODO case to show animation? or return nothing?
        -- TODO return smth to signal missing closing but open is present, as a second arg
        return lines, M.ThinkingStatus.Thinking
    end
    local stripped_text = text:sub(close_end + 1)
    return vim.split(stripped_text, "\n"), M.ThinkingStatus.DoneThinking
end

return M
