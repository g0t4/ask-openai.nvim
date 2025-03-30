local log = require("ask-openai.prediction.logger").predictions() -- TODO rename to just ask-openai logger in general
local M = {}

function M.get_visual_selection()
    -- FYI getpos returns a byte index, getcharpos() returns a char index (prefer it)
    --   getcharpos also resolves the issue with v:maxcol as the returned col number (i.e. in visual line mode selection)
    local _, start_line, start_col, _ = unpack(vim.fn.getcharpos("'<"))
    local _, end_line, end_col, _ = unpack(vim.fn.getcharpos("'>"))
    local lines = vim.fn.getline(start_line, end_line)

    log:info("GETCHARPOS start(line=" .. start_line .. ",col=" .. start_col
        .. ") end(line=" .. end_line .. ",col=" .. end_col .. ")")

    -- TESTs for visual line mode:
    -- - empty line selected (not across to next line) -- has end_line = start_line
    -- - empty line selected by shift+V j    -- has end_line > start_line
    -- FYI these tests are working in my initial testing

    if #lines == 0 then return "" end

    lines[#lines] = string.sub(lines[#lines], 1, end_col)
    lines[1] = string.sub(lines[1], start_col)

    return vim.fn.join(lines, "\n"), start_line, start_col, end_line, end_col
end

return M
