-- Map <leader>b to print the cursor position.
vim.keymap.set({ 'n', 'v' }, '<leader>b', function()
    vim.print(GetPos.CurrentSelection())
end, { desc = "Print cursor position (getpos)" })


-- TODO! ! use this with selection logic and class in rewrites  (maybe predictions too)


--- wrapper for getpos(expr)
_G.GetPos = {}

---@class GetPosPosition
---@field line_b1 integer
---@field col_b1 integer
_G.GetPosPosition = {}

---@return GetPosPosition
function GetPos.CursorPosition()
    return GetPos._line_and_column(".")
end

---@return GetPosPosition
function GetPos.OtherEndOfSelection()
    -- if not in visual mode, this will return CursorPosition (same as ".")
    return GetPos._line_and_column("v")
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
function GetPos.CurrentSelection()
    local dot = GetPos._line_and_column(".")
    local v = GetPos._line_and_column("v")

    local mode = vim.fn.mode()
    local last_visual_mode = vim.fn.visualmode()
    local linewise = mode == "V" or (mode ~= "v" and last_visual_mode == "V")

    local start_line, start_col, end_line, end_col
    if dot.line_b1 < v.line_b1 or (dot.line_b1 == v.line_b1 and dot.col_b1 <= v.col_b1) then
        -- do the selection points refer to a linewise range OR charwise
        -- charwise = opposite linewise
        return {
            start_line_b1    = dot.line_b1,
            start_col_b1     = dot.col_b1,
            end_line_b1      = v.line_b1,
            end_col_b1       = v.col_b1,
            mode             = mode,
            last_visual_mode = last_visual_mode,
            linewise         = linewise,
        }
    else
        return {
            start_line_b1    = v.line_b1,
            start_col_b1     = v.col_b1,
            end_line_b1      = dot.line_b1,
            end_col_b1       = dot.col_b1,
            mode             = mode,
            last_visual_mode = last_visual_mode,
            linewise         = linewise,
        }
    end
end

---Returns the current selection in 1‑indexed line/column coordinates.
---The order is always start → end regardless of cursor direction.
---@return GetPosSelectionRange
function GetPos.LastSelection()
    local lt = GetPos._line_and_column("'<")
    local gt = GetPos._line_and_column("'>")

    local mode = vim.fn.mode()
    local last_visual_mode = vim.fn.visualmode()
    local linewise = mode == "V" or (mode ~= "v" and last_visual_mode == "V")
    return {
        start_line_b1 = lt.line_b1,
        start_col_b1 = lt.col_b1,
        end_line_b1 = gt.line_b1,
        end_col_b1 = gt.col_b1,
        mode = mode,
        last_visual_mode = last_visual_mode,
        linewise = linewise,
    }
end

---@return GetPosPosition
function GetPos.LastLineOfBuffer()
    return GetPos._line_and_column("$")
end

---@return GetPosPosition
function GetPos.LastVisibleLine()
    return GetPos._line_and_column("w$")
end

---@return GetPosPosition
function GetPos.FirstVisibleLine()
    return GetPos._line_and_column("w0")
end

---@param expr string
---@return GetPosPosition
function GetPos._line_and_column(expr)
    -- FYI offset has to do with virtualedit (when cursor is allowed to stop on non-char positions)
    local bufnr, line_base1, col_base1, offset = unpack(vim.fn.getpos(expr))
    return { line_b1 = line_base1, col_b1 = col_base1 }
end
