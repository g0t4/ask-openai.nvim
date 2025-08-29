local log = require("ask-openai.logs.logger").predictions()

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
    local current_mode = vim.fn.mode()
    local last_visualmode = vim.fn.visualmode()
    -- print(vim.inspect({ current_mode = current_mode, last_visualmode = last_visualmode }))
    -- TODO use current_mode (if selection) to simplify getting lines for V (visual linewise), v (charwise), Ctrl-V (blockwise - not supported)
    -- if mode == "v" or "V" currently
    if current_mode == "v" then
        -- local cursor_pos = vim.fn.getpos(".")
        -- local other_pos = vim.fn.getpos("v")
        -- -- TODO col + lines
    elseif current_mode == "V" then
        -- -- TODO can I reuse this with last_visualmode too and just pass diff "'>" instead of "v" to helper function?
        -- local cursor_pos = vim.fn.getpos(".")
        -- local other_pos = vim.fn.getpos("v")
        -- print(vim.inspect({ cursor_pos = cursor_pos, other_pos = other_pos }))
        -- local line1 = cursor_pos[2]
        -- local line2 = other_pos[2]
        -- -- if line1 > line2 then
        -- --     TODO test this, don't just write it
        -- --     local tmp = other_pos
        -- --     other_pos = cursor_pos
        -- --     cursor_pos = tmp
        -- --     tmp = line1
        -- --     line1 = line2
        -- --     line2 = line1
        -- -- end
        -- print(vim.inspect({ line1 = line1, line2 = line2 }))
        -- -- TODO lines only => so? 0/1 for first line, -1 for second? OR maybe have a diff selection that knows types? a selection for lines only vs char positions
    else
        if last_visualmode == "v" then
            -- local start_pos = vim.fn.getpos("'<")
            -- local end_pos = vim.fn.getpos("'>")
            -- -- get char/line positions from getpos("'<") and getpos("'>")
            -- -- TODO
        elseif last_visualmode == "V" then
            -- local start_pos = vim.fn.getpos("'<")
            -- local end_pos = vim.fn.getpos("'>")
            -- -- get lines from getpos("'<") and getpos("'>")
            -- -- TODO
        else
            -- FYI this is handling empty case now!
            -- return empty @ current cursor position
            local row_1indexed, col_0indexed = unpack(vim.api.nvim_win_get_cursor(0))
            start_line_1indexed = row_1indexed
            start_col_1indexed = col_0indexed + 1
            -- copy to end position
            end_line_1indexed = start_line_1indexed
            end_col_1indexed = start_col_1indexed
            return Selection:new({}, start_line_1indexed, start_col_1indexed, end_line_1indexed, end_col_1indexed)
        end
    end

    --   change all of this to conside this when getting last selection
    --
    -- TODO I am not yet using window_id/buffer_number... maybe comment it out until I absolutely need it?
    local buffer_number = vim.api.nvim_win_get_buf(window_id)

    -- getpos returns a byte index, getcharpos() returns a char index
    -- * getcharpos also resolves the issue with v:maxcol as the returned col number (i.e. in visual line mode selection)
    -- CRAP! getcharpos might be an issue.. b/c it is char wise... so if I have a tab it will count as 1 not 4 chars
    --
    local _, start_line_1indexed, start_col_1indexed, _ = unpack(vim.fn.getcharpos("'<"))
    -- start_line/start_col are 1-indexed (from register value)
    local _, end_line_1indexed, end_col_1indexed, _ = unpack(vim.fn.getcharpos("'>"))
    -- print(vim.inspect({ start_line_1indexed = start_line_1indexed, start_col_1indexed = start_col_1indexed }))

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
    -- print(vim.inspect({ selected_lines = selected_lines }))

    if #selected_lines == 0 then
        log:info("HOW DID WE GET HERE!? this shouldn't happen!")
        return Selection:new({}, start_line_1indexed, start_col_1indexed, end_line_1indexed, end_col_1indexed)
    end

    -- Truncate the last line to the specified end column
    local last_line = selected_lines[#selected_lines]
    -- print(vim.inspect({ last_line = last_line }))
    selected_lines[#selected_lines] = string.sub(last_line, 1, end_col_1indexed)
    -- print(vim.inspect({ selected_lines = selected_lines }))

    -- Truncate the first line thru the specified start column
    local first_line = selected_lines[1]
    selected_lines[1] = string.sub(first_line, start_col_1indexed)
    -- print(vim.inspect({ selected_lines = selected_lines }))

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
