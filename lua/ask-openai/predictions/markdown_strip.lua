--- Helpers to strip markdown code fences that models sometimes wrap their
--- completions in (```language ... ``` or `...`).
---
--- Because output streams token-by-token, these helpers are conservative:
--- a leading fence is only stripped once it is a complete, newline-terminated
--- line (so a partially-streamed ```lang is never eaten prematurely), and a
--- trailing fence is stripped once it is the final line.
---
--- @class MarkdownStrip
local M = {}

--- Strip a leading triple-backtick fence line (with optional language) plus
--- its trailing newline, e.g. "```lua\n" or "```\n".
--- Only strips a fence that is newline-terminated; a partial "```lua" (no
--- newline yet) is left alone so a streaming fence is never eaten early.
--- @param text string
--- @return string
function M.strip_leading_fence(text)
    local stripped = text:gsub("^```%S*\n", "")
    return stripped
end

--- Strip a trailing triple-backtick fence line (with optional language).
--- Handles a closing fence at the very end ("...\n```") as well as one
--- followed by a newline ("...\n```\n").
--- @param text string
--- @return string
function M.strip_trailing_fence(text)
    -- closing fence line followed by newline:  "...\n```\n"  ->  "...\n"
    local stripped = text:gsub("\n```%S*\n$", "\n")
    -- closing fence at very end:  "...\n```"  ->  "..."
    stripped = stripped:gsub("\n```%S*$", "")
    -- a bare fence is the entire text:  "```"  ->  ""
    -- (exactly three backticks; a partial "```lua" without a newline is left
    --  alone so a streaming opening fence is never eaten early)
    stripped = stripped:gsub("^```$", "")
    return stripped
end

--- Strip a single leading/trailing backtick used as an inline code wrapper,
--- e.g. "`local x = 1`" -> "local x = 1".
--- Only strips when each end is exactly one backtick (not part of a longer
--- run), so a partially-streamed triple fence is never consumed.
--- Also handles a trailing newline after the closing backtick (e.g.
--- "`local x = 1`\n" -> "local x = 1"): models sometimes emit the newline as
--- part of the wrapper, so it is stripped along with the backticks.
--- @param text string
--- @return string
function M.strip_inline_backticks(text)
    local starts_single = text:sub(1, 1) == "`" and text:sub(1, 2) ~= "``"

    -- Peek past a trailing newline (e.g. "`code`\n") when checking for the
    -- closing backtick; the newline is part of the model's wrapper, not the
    -- completion content.
    local has_trailing_newline = text:sub(-1) == "\n"
    local body = text
    if has_trailing_newline then
        body = text:sub(1, -2)
    end

    local ends_single = body:sub(-1) == "`" and body:sub(-2) ~= "``"
    if starts_single and ends_single and #body > 2 then
        return body:sub(2, -2)
    end
    return text
end

--- Apply all markdown fence / backtick stripping to a completion string.
--- @param text string
--- @return string
function M.strip(text)
    local stripped = M.strip_leading_fence(text)
    stripped = M.strip_trailing_fence(stripped)
    stripped = M.strip_inline_backticks(stripped)
    return stripped
end

return M
