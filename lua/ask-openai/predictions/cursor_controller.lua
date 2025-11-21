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
    local new_line_base0, new_col_base0
    if #inserted_lines == 1 then
        new_line_base0 = cursor.line_base0

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

---@class CursorInfo
---@field line_base0 integer
---@field line_base1 integer
---@field col_base0 integer
---@field col_base1 integer

---@return CursorInfo
function CursorController:get_cursor_position()
    local line_base1, col_base0 = unpack(vim.api.nvim_win_get_cursor(self.window_id)) -- (1,0)-indexed (row,col)
    return {
        line_base1 = line_base1,
        line_base0 = line_base1 - 1,
        col_base0 = col_base0,
        col_base1 = col_base0 + 1,
    }
end

return CursorController
