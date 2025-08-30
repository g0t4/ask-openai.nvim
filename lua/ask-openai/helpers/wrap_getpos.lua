-- Map <leader>b to print the cursor position.
vim.keymap.set({ 'n', 'v' }, '<leader>b', function()
    vim.print(GetPos.SelectionRange_Line1Col1())
end, { desc = "Print cursor position (getpos)" })



_G.GetPos = {}

--- getpos(".")
function GetPos.CursorPosition_Line1Col1()
    return GetPos.Line1Col1(".")
end

function GetPos.OtherEndOfSelection_Line1Col1()
    -- if not in visual mode, this will return CursorPosition (same as ".")
    return GetPos.Line1Col1("v")
end

---@class GetPosSelectionRange
---@field start_line_b1 integer
---@field start_col_b1 integer
---@field end_line_b1 integer
---@field end_col_b1 integer
_G.GetPosSelectionRange = {}


---Returns the selection range in 1‑indexed line/column coordinates.
---The order is always start → end regardless of cursor direction.
---@return GetPosSelectionRange
function GetPos.SelectionRange_Line1Col1()
    local dot_line_base1, dot_col_base1 = GetPos.Line1Col1(".")
    local v_line_base1, v_col_base1 = GetPos.Line1Col1("v")

    local start_line, start_col, end_line, end_col
    if dot_line_base1 < v_line_base1 or (dot_line_base1 == v_line_base1 and dot_col_base1 <= v_col_base1) then
        return {
            start_line_b1 = dot_line_base1,
            start_col_b1  = dot_col_base1,
            end_line_b1   = v_line_base1,
            end_col_b1    = v_col_base1,
        }
    else
        return {
            start_line_b1 = v_line_base1,
            start_col_b1  = v_col_base1,
            end_line_b1   = dot_line_base1,
            end_col_b1    = dot_col_base1,
        }
    end
end

---Returns the current selection in 1‑indexed line/column coordinates.
---The order is always start → end regardless of cursor direction.
---@return GetPosSelectionRange
function GetPos.LastSelection()
    local lt_line_base1, lt_col_base1 = GetPos.Line1Col1("'<")
    local gt_line_base1, gt_col_base1 = GetPos.Line1Col1("'>")
    return {
        start_line_b1 = lt_line_base1,
        start_col_b1 = lt_col_base1,
        end_line_b1 = gt_line_base1,
        end_col_b1 = gt_col_base1,
    }
end

function GetPos.LastLineOfBuffer_Line1Col1()
    return GetPos.Line1Col1("$")
end

function GetPos.LastVisibleLine_Line1Col1()
    return GetPos.Line1Col1("w$")
end

function GetPos.FirstVisibleLine_Line1Col1()
    return GetPos.Line1Col1("w0")
end

---@param expr string
function GetPos.Line1Col1(expr)
    -- FYI offset has to do with virtualedit (when cursor is allowed to stop on non-char positions)
    local bufnr, lnum_base1, col_base1, offset = unpack(vim.fn.getpos(expr))
    return lnum_base1, col_base1
end
