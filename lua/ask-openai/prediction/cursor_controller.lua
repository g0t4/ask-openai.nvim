---@class CursorController
---@field window_id integer
local CursorController = {}
CursorController.__index = CursorController

---@param window_id integer? # defaults to current window (0)
---@return CursorController
function CursorController:new(window_id)
    local self = setmetatable({}, CursorController)
    self.window_id = window_id or 0
    return self
end

---Calculate new cursor position after inserting `text` at the current cursor.
---Handles multiline text and returns both 0- and 1-indexed coordinates.
---@param inserted_lines string[]
---@param cursor CursorInfo
---@return CursorInfo
function CursorController:calc_new_position(cursor, inserted_lines)
    -- TODO I am itching to refactor setting these up here and then overriding in all but one case!
    local new_line_base0 = cursor.line_base0
    local new_col_base0 = cursor.col_base0

    if #inserted_lines == 1 then
        new_col_base0 = cursor.col_base0 + #inserted_lines[1]
    else
        -- minus 1 because first line is cursor line (IOTW already moved to it)
        move_down_lines = #inserted_lines - 1
        new_line_base0 = cursor.line_base0 + move_down_lines

        new_col_base0 = #inserted_lines[#inserted_lines] -- to last inserted character on the last line
    end

    return {
        line_base0 = new_line_base0,
        line_base1 = new_line_base0 + 1,
        col_base0 = new_col_base0,
        col_base1 = new_col_base0 + 1,
    }
end

---@param cursor CursorInfo
---@param inserted_lines string[]
function CursorController:move_cursor_after_insert(cursor, inserted_lines)
    -- TODO likley I will merge this with inserting the text, I think it's all going to work well together
    -- FYI for now this gets the calculations CORRECT to fix the bug in cursor movement in accept all with a middle of the line FIM so let's plug this in and use it for now
    local new_cursor = self:calc_new_position(cursor, inserted_lines)
    vim.api.nvim_win_set_cursor(self.window_id, { new_cursor.line_base1, new_cursor.col_base0 }) -- (1,0)-indexed
end

return CursorController
