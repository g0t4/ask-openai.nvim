local log = require("ask-openai.prediction.logger").predictions()

---@class Selection
---@field original_text string
---@field _start_line_0indexed integer
---@field _start_col_0indexed integer
---@field _end_line_0indexed integer
---@field _end_col_0indexed integer
local Selection = {}

function Selection:new(selected_lines, start_line_1indexed, start_col_1indexed, end_line_1indexed, end_col_1indexed)
    local obj = {
        original_text = vim.fn.join(selected_lines, "\n"),
        _start_line_0indexed = start_line_1indexed - 1,
        _start_col_0indexed = start_col_1indexed - 1,
        _end_line_0indexed = end_line_1indexed - 1,
        _end_col_0indexed = end_col_1indexed - 1,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Selection:is_empty()
    return self.original_text == nil or self.original_text == ""
end

function Selection:to_str()
    return "Selection: " .. self:range_str()
end

function Selection:start_line_0indexed()
    return self._start_line_0indexed
end

function Selection:start_col_0indexed()
    return self._start_col_0indexed
end

function Selection:end_line_0indexed()
    return self._end_line_0indexed
end

function Selection:end_col_0indexed()
    return self._end_col_0indexed
end

function Selection:start_line_1indexed()
    return self._start_line_0indexed + 1
end

function Selection:start_col_1indexed()
    return self._start_col_0indexed + 1
end

function Selection:end_line_1indexed()
    return self._end_line_0indexed + 1
end

function Selection:end_col_1indexed()
    return self._end_col_0indexed + 1
end

function Selection:log_info(message)
    log:info(message, self:to_str())
end

function Selection._get_visual_selection_for_window_id(window_id)
    -- TODO I am not yet using window_id/buffer_number... maybe comment it out until I absolutely need it?
    local buffer_number = vim.api.nvim_win_get_buf(window_id)

    -- getpos returns a byte index, getcharpos() returns a char index
    -- * getcharpos also resolves the issue with v:maxcol as the returned col number (i.e. in visual line mode selection)
    local _, start_line_1indexed, start_col_1indexed, _ = unpack(vim.fn.getcharpos("'<"))
    -- start_line/start_col are 1-indexed (from register value)
    local _, end_line_1indexed, end_col_1indexed, _ = unpack(vim.fn.getcharpos("'>"))
    if start_line_1indexed == 0 and start_col_1indexed == 0 and end_line_1indexed == 0 and end_col_1indexed == 0 then
        log:info("no selection, using cursor position with empty selection")
        local row_1indexed, col_0indexed = unpack(vim.api.nvim_win_get_cursor(0))
        start_line_1indexed = row_1indexed
        start_col_1indexed = col_0indexed + 1
        -- copy to end position
        end_line_1indexed = start_line_1indexed
        end_col_1indexed = start_col_1indexed
        return Selection:new({}, start_line_1indexed, start_col_1indexed, end_line_1indexed, end_col_1indexed)
    end

    -- end_line/end_col are 1-indexed, end_col appears to be the cursor position at the end of a selection
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

    -- getline is 1-indexed, end-inclusive (optional)
    local selected_lines = vim.fn.getline(start_line_1indexed, end_line_1indexed)

    if #selected_lines == 0 then
        log:info("HOW DID WE GET HERE!? this shouldn't happen!")
        return Selection:new({}, start_line_1indexed, start_col_1indexed, end_line_1indexed, end_col_1indexed)
    end

    -- Truncate the last line to the specified end column
    local last_line = selected_lines[#selected_lines]
    selected_lines[#selected_lines] = string.sub(last_line, 1, end_col_1indexed)

    -- Truncate the first line thru the specified start column
    local first_line = selected_lines[1]
    selected_lines[1] = string.sub(first_line, start_col_1indexed)

    local selection = Selection:new(selected_lines, start_line_1indexed, start_col_1indexed, end_line_1indexed, end_col_1indexed)
    selection:log_info("get_visual_selection():")
    return selection
end

---@return Selection
function Selection.get_visual_selection_for_current_window()
    local current_window_id = vim.api.nvim_get_current_win()
    return Selection._get_visual_selection_for_window_id(current_window_id)
end

--- Set the selection and get a reference to it.
---TODO is List<integer,integer> right for the type... table w/ two numbers in it?
---@param start_pos List<integer,integer>
---@param end_pos List<integer,integer>
---@return Selection
function Selection.set_selection_from_range(start_pos, end_pos)
    vim.api.nvim_win_set_cursor(0, start_pos)
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(0, end_pos)
    vim.cmd("normal! v")
    return Selection.get_visual_selection_for_current_window()
end

function Selection:range_str()
    local range = string.format(
        "[r%d,c%d]-[r%d,c%d] 1-indexed",
        self:start_line_1indexed(),
        self:start_col_1indexed(),
        self:end_line_1indexed(),
        self:end_col_1indexed()
    )
    if self:is_empty() then
        range = range .. " (empty)"
    end
    return range
end

function Selection:range_str_0indexed()
    local range = string.format(
        "[r%d,c%d]-[r%d,c%d] 0-indexed",
        self:start_line_0indexed(),
        self:start_col_0indexed(),
        self:end_line_0indexed(),
        self:end_col_0indexed()
    )
    if self:is_empty() then
        range = range .. " (empty)"
    end
    return range
end

return Selection
