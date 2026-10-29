-- Format reasoning content with a thinking emoji prefix and indentation so
-- every line aligns past the emoji (matches the Python chat viewer).
local M = {}

-- The thinking emoji shown before reasoning content.
local THINKING_EMOJI = "💭"

---@param text string -- reasoning content (may span multiple lines)
---@return string
function M.format_reasoning(text)
    local lines = vim.split(text, "\n")
    -- 💭 is a wide character (2 cells); leave one space of padding after it.
    local indent = string.rep(" ", vim.fn.strdisplaywidth(THINKING_EMOJI) + 1)
    for i, line in ipairs(lines) do
        if i == 1 then
            lines[i] = THINKING_EMOJI .. " " .. line
        elseif line ~= "" then
            lines[i] = indent .. line
        end
    end
    return table.concat(lines, "\n")
end

return M
