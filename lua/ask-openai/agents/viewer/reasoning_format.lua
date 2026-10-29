-- Format reasoning content with a thinking emoji prefix and indentation so
-- every line aligns past the emoji (matches the Python chat viewer).
local M = {}

-- The thinking emoji shown before reasoning content.
local THINKING_EMOJI = "💭"

-- 💭 is a wide character (2 cells); leave one space of padding after it.
-- Computed once at load time (main loop) so format_reasoning never calls a
-- fast-path-restricted API (vim.fn.strdisplaywidth) from the live viewer's
-- async SSE callback.
local INDENT = string.rep(" ", vim.fn.strdisplaywidth(THINKING_EMOJI) + 1)

---@param text string -- reasoning content (may span multiple lines)
---@return string
function M.format_reasoning(text)
    local lines = vim.split(text, "\n")
    for i, line in ipairs(lines) do
        if i == 1 then
            lines[i] = THINKING_EMOJI .. " " .. line
        elseif line ~= "" then
            lines[i] = INDENT .. line
        end
    end
    return table.concat(lines, "\n")
end

return M
