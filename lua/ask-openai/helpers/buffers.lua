local log = require("ask-openai.prediction.logger").predictions() -- TODO rename to just ask-openai logger in general
local M = {}

local Selection = {}
function Selection:new(selected_lines, start_line, start_col, end_line, end_col)
    local obj = {
        original_text = vim.fn.join(selected_lines, "\n"),
        start_line = start_line,
        start_col = start_col,
        end_line = end_line,
        end_col = end_col,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Selection:is_empty()
    return self.original_text == nil or self.original_text == ""
end

function Selection:log_info()
    log:info(string.format(
        "Original text: %s\nstart_line: %d\nstart_col: %d\nend_line: %d\nend_col: %d",
        self.original_text, self.start_line, self.start_col, self.end_line, self.end_col
    ))
end

function M.get_visual_selection()
    -- FYI getpos returns a byte index, getcharpos() returns a char index (prefer it)
    --   getcharpos also resolves the issue with v:maxcol as the returned col number (i.e. in visual line mode selection)
    local _, start_line_1based, start_col_1based, _ = unpack(vim.fn.getcharpos("'<"))
    -- start_line/start_col are 1-based (from register value)
    local _, end_line_1based, end_col_1based_exclusive, _ = unpack(vim.fn.getcharpos("'>"))
    -- end_line/end_col are 1-based, end_col is end-exclusive (end_col is location of cursor when text was selected)
    -- another possible issue... if selection was made in visual linewise mode, the end col seems to be inclusive?!
    --
    -- key modes (at least) to consider:
    --   normal mode
    --   visual linewise, charwise and blockwise
    --   select mode
    --
    -- FYI :h selection (vim.o.selection) => visual/select modes:
    --   right now selection value=inclusive in my config
    --   inclusive=yes/no is last char of selection included
    --   "past line"=yes/no
    --   tackle this (if its even an issue) when I encounter a problem with it

    local selected_lines = vim.fn.getline(start_line_1based, end_line_1based)

    log:info("GETCHARPOS start(line=" .. start_line_1based .. ",col=" .. start_col_1based
        .. ") end(line=" .. end_line_1based .. ",col=" .. end_col_1based_exclusive .. ")")

    -- TESTs for visual line mode:
    -- - empty line selected (not across to next line) -- has end_line = start_line
    -- - empty line selected by shift+V j    -- has end_line > start_line
    -- FYI these tests are working in my initial testing

    if #selected_lines == 0 then return "" end

    -- TODO add testing and review accuracy of selecting a subset of the start and end line separately
    -- Truncate the last line to the specified end column
    selected_lines[#selected_lines] = string.sub(selected_lines[#selected_lines], 1, end_col_1based_exclusive)
    -- TODO end column calc is off by one
    -- Truncate the first line thru the specified start column
    selected_lines[1] = string.sub(selected_lines[1], start_col_1based)

    return Selection:new(selected_lines, start_line_1based, start_col_1based, end_line_1based, end_col_1based_exclusive)
end

return M
