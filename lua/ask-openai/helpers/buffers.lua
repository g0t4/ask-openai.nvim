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

function Selection:to_str(as_0based)
    as_0based = as_0based or false
    if as_0based then
        return
            "Selection: 0-based start(line=" .. (self.start_line_1based - 1)
            .. ",col=" .. (self.start_col_1based - 1)
            .. ") end(line=" .. (self.end_line_1based - 1)
            .. ",col=" .. (self.end_col_1based - 1)
            .. ") (" .. self.original_text .. ")"
    end
    return
        "Selection: 1-based start(line=" .. self.start_line_1based
        .. ",col=" .. self.start_col_1based
        .. ") end(line=" .. self.end_line_1based
        .. ",col=" .. self.end_col_1based
        .. ") (" .. self.original_text .. ")"
end

function Selection:log_info(as_0based)
    log:info(self:to_str(as_0based))
end

function M.get_visual_selection()
    -- FYI getpos returns a byte index, getcharpos() returns a char index (prefer it)
    --   getcharpos also resolves the issue with v:maxcol as the returned col number (i.e. in visual line mode selection)
    local _, start_line_1based, start_col_1based, _ = unpack(vim.fn.getcharpos("'<"))
    -- start_line/start_col are 1-based (from register value)
    local _, end_line_1based, end_col_1based, _ = unpack(vim.fn.getcharpos("'>"))
    -- end_line/end_col are 1-based, end_col appears to be the cursor position at the end of a selection
    --
    -- FYI, while in visual modes (char/line) the current selection is NOT the last selection
    --   if this lua func is called from a keymap using a lua handler, the WIP selection won't be available yet
    --   but, if this func is called indirectly via a vim command, the selection is "committed" as last selection
    --   executing a command logically seems like finalizing the selection, so that makes sense
    --   also, I get the rationale that calling a func is useful b/c that func could help move the cursor to select desired text and so you won't want to "commit" it yet
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

    if #selected_lines == 0 then return "" end

    -- Truncate the last line to the specified end column
    local last_line = selected_lines[#selected_lines]
    selected_lines[#selected_lines] = string.sub(last_line, 1, end_col_1based)

    -- Truncate the first line thru the specified start column
    local first_line = selected_lines[1]
    selected_lines[1] = string.sub(first_line, start_col_1based)

    local selection = Selection:new(selected_lines, start_line_1based, start_col_1based, end_line_1based, end_col_1based)
    selection:log_info()
    return selection
end

function M.dump_last_seletion()
    local selection = M.get_visual_selection()
    print(vim.inspect(selection))
end

function split_lines_skip_empties(string)
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
