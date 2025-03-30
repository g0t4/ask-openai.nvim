local log = require("ask-openai.prediction.logger").predictions() -- TODO rename to just ask-openai logger in general
local M = {}

local Selection = {}
function Selection:new(selected_lines, start_line_1based, start_col_1based, end_line_1based, end_col_1based)
    local obj = {
        original_text = vim.fn.join(selected_lines, "\n"),
        start_line_1based = start_line_1based,
        start_col_1based = start_col_1based,
        end_line_1based = end_line_1based,
        end_col_1based = end_col_1based,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Selection:is_empty()
    return self.original_text == nil or self.original_text == ""
end

function Selection:to_str()
    return
        "Selection: start(line=" .. self.start_line_1based
        .. ",col=" .. self.start_col_1based
        .. ") end(line=" .. self.end_line_1based
        .. ",col=" .. self.end_col_1based
        .. ")"
end

function Selection:log_info()
    log:info(self:to_str())
end

function M.get_visual_selection()
    -- FYI getpos returns a byte index, getcharpos() returns a char index (prefer it)
    --   getcharpos also resolves the issue with v:maxcol as the returned col number (i.e. in visual line mode selection)
    local _, start_line_1based, start_col_1based, _ = unpack(vim.fn.getcharpos("'<"))
    -- start_line/start_col are 1-based (from register value)
    local _, end_line_1based, end_col_1based, _ = unpack(vim.fn.getcharpos("'>"))
    -- end_line/end_col are 1-based, end_col appears to be the cursor position at the end of a selection
    -- another possible issue... if selection was made in visual linewise mode, the end col seems to be inclusive?!
    --   in visual mode keymap for `<leader>ads` if selecting a subset of line it is still reeporting end as end of line?!
    --      and then if I exit visual mode (back to normal) then ads reports correct end_col based on subset selected
    --
    -- key modes (at least) to consider:
    --   normal mode
    --   visual linewise, charwise and blockwise
    --   select mode
    --
    -- TESTs for visual line mode:
    -- - empty line selected (not across to next line) -- has end_line = start_line
    -- - empty line selected by shift+V j    -- has end_line > start_line
    -- PRN add unit tests if this gets more complicated
    --
    -- FYI :h selection (vim.o.selection) => visual/select modes:
    --   right now selection value=inclusive in my config
    --   inclusive=yes/no is last char of selection included
    --   "past line"=yes/no
    --   tackle this (if its even an issue) when I encounter a problem with it
    --

    -- getline is 1-based, end-inclusive (optional)
    local selected_lines = vim.fn.getline(start_line_1based, end_line_1based)

    log:info("GETCHARPOS start(line=" .. start_line_1based .. ",col=" .. start_col_1based
        .. ") end(line=" .. end_line_1based .. ",col=" .. end_col_1based .. ")")


    if #selected_lines == 0 then return "" end

    -- Truncate the last line to the specified end column
    local last_line = selected_lines[#selected_lines]
    selected_lines[#selected_lines] = string.sub(last_line, 1, end_col_1based)

    -- Truncate the first line thru the specified start column
    local first_line = selected_lines[1]
    selected_lines[1] = string.sub(first_line, start_col_1based)

    return Selection:new(selected_lines, start_line_1based, start_col_1based, end_line_1based, end_col_1based)
end

function M.dump_last_seletion()
    local selection = M.get_visual_selection()
    print(vim.inspect(selection))
end

return M
