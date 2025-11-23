--- wrapper for getpos(expr)
--- take the pain out of getting cursor position and selections (last/current)
---@class GetPosModule
local GetPos = {}


-- TODO! ! use this for selection in frontends: rewrites, questions, predictions, etc?

function setup_for_testing()
    -- Map <leader>b to print the cursor position.
    vim.keymap.set({ 'n', 'v' }, '<leader>b', function()
        vim.print(GetPos.CurrentSelection())
    end, { desc = "Print cursor position (getpos)" })
end

setup_for_testing()

---@class GetPosPosition
---@field line_b1 integer
---@field col_b1 integer
_G.GetPosPosition = {}

---@param expr string
---@return GetPosPosition
local function getpos_only_line_and_column(expr)
    -- FYI offset has to do with virtualedit (when cursor is allowed to stop on non-char positions)
    local bufnr, line_base1, col_base1, offset = unpack(vim.fn.getpos(expr))
    return { line_b1 = line_base1, col_b1 = col_base1 }
end

---@return GetPosPosition
function GetPos.CursorPosition()
    return getpos_only_line_and_column(".")
end

---@return GetPosPosition
function GetPos.OtherEndOfSelection()
    -- if not in visual mode, this will return CursorPosition (same as ".")
    return getpos_only_line_and_column("v")
end

---@class GetPosSelectionRange
---@field start_line_b1 integer
---@field start_col_b1 integer
---@field end_line_b1 integer
---@field end_col_b1 integer
_G.GetPosSelectionRange = {}

local instance_mt = { __index = GetPosSelectionRange }
function GetPosSelectionRange:new(range)
    assert(range ~= nil, "Missing required argument `range`, did you forgot to use :new()? do not use .new() without passing GetPosSelectionRange as first arg!")

    -- ❤️ naming this "instance"
    -- doesn't clobber "self" (which in this case is the GetPosSelectionRange class object)
    local instance = range or {}
    setmetatable(instance, instance_mt)
    return instance
end

--- This is a "line touches count",
--- which ignores column offsets within each line
---@return integer num_lines_touched
function GetPosSelectionRange:line_count()
    return self.end_line_b1 - self.start_line_b1 + 1
end

-- TODO GetPosSelectionRange:*_base0() calculations

---Returns the selection range in 1‑indexed line/column coordinates.
---The order is always start → end regardless of cursor direction.
---@return GetPosSelectionRange
function GetPos.CurrentSelection()
    local dot = getpos_only_line_and_column(".")
    local v = getpos_only_line_and_column("v")

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
    local lt = getpos_only_line_and_column("'<")
    local gt = getpos_only_line_and_column("'>")

    local mode = vim.fn.mode()
    local last_visual_mode = vim.fn.visualmode()
    local linewise = mode == "V" or (mode ~= "v" and last_visual_mode == "V")
    return GetPosSelectionRange:new {
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
    return getpos_only_line_and_column("$")
end

---@return GetPosPosition
function GetPos.LastVisibleLine()
    return getpos_only_line_and_column("w$")
end

---@return GetPosPosition
function GetPos.FirstVisibleLine()
    return getpos_only_line_and_column("w0")
end

return GetPos
