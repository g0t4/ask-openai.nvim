local M = {
    dots = require("ask-openai.rewrites.thinking.dots"),
}

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

return M
