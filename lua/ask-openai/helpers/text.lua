local M = {}

function M.split_lines(text)
    -- preserve empty lines too
    return vim.split(text, "\n")
end

function M.split_lines_skip_empties(string)
    -- TODO search for other uses of this and replace them! (where I manually split and check blanks)
    -- wrapper as a reminder really
    local lines = vim.split(string, "\n", { trimempty = true })
    local keep = {}
    for _, line in ipairs(lines) do
        if line:match("%S") then
            table.insert(keep, line)
        end
    end
    return keep
end

return M
