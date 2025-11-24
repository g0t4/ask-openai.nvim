--- wrapper for getpos(expr)
--- take the pain out of getting cursor position and selections (last/current)
---@class GetPosModule
local GetPos = {}


-- TODO! ! use this for selection in frontends: rewrites, questions, predictions, etc?

function setup_for_testing()
    -- Map <leader>b to print the cursor position.
    vim.keymap.set({ 'n', 'v' }, '<leader>b', function()
        vim.print(GetPos.current_selection())
    end, { desc = "Print cursor position (getpos)" })
end

setup_for_testing()

---@class GetPosPosition
---@field line_base1 integer
---@field col_base1 integer
_G.GetPosPosition = {}

---@param expr string
---@return GetPosPosition
local function getpos_only_line_and_column(expr)
    -- FYI offset has to do with virtualedit (when cursor is allowed to stop on non-char positions)
    local bufnr, line_base1, col_base1, offset = unpack(vim.fn.getpos(expr))
    return { line_base1 = line_base1, col_base1 = col_base1 }
end

---@return GetPosPosition
function GetPos.cursor_position()
    -- TODO add behavior to the result => i.e. cursor:base0() methods (like what I did with GetPosSelectionRange)
    return getpos_only_line_and_column(".")
end

---@return GetPosPosition
function GetPos.other_end_of_selection()
    -- if not in visual mode, this will return CursorPosition (same as ".")
    return getpos_only_line_and_column("v")
end

---@class GetPosSelectionRange
---@field start_line_base1 integer
---@field start_col_base1 integer
---@field end_line_base1 integer
---@field end_col_base1 integer
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
    -- FYI this is moreso intended for a linewise selection
    -- but could be useful in a charwise too
    return self.end_line_base1 - self.start_line_base1 + 1
end

function GetPosSelectionRange:start_line_base0()
    return self.start_line_base1 - 1
end

function GetPosSelectionRange:end_line_base0()
    return self.end_line_base1 - 1
end

function GetPosSelectionRange:start_col_base0()
    return self.start_col_base1 - 1
end

function GetPosSelectionRange:end_col_base0()
    return self.end_col_base1 - 1
end

--- helper to determine if there was a prior selection (or not)
function GetPosSelectionRange:no_prior_selection()
    return self.last_visual_mode == ""
end

-- TODO GetPosSelectionRange:*_base0() calculations

---Returns the selection range in 1‑indexed line/column coordinates.
---The order is always start → end regardless of cursor direction.
---@return GetPosSelectionRange
function GetPos.current_selection()
    local dot = getpos_only_line_and_column(".")
    local v = getpos_only_line_and_column("v")

    local mode = vim.fn.mode()
    local last_visual_mode = vim.fn.visualmode()
    local linewise = mode == "V" or (mode ~= "v" and last_visual_mode == "V")

    local start_line, start_col, end_line, end_col
    if dot.line_base1 < v.line_base1 or (dot.line_base1 == v.line_base1 and dot.col_base1 <= v.col_base1) then
        -- do the selection points refer to a linewise range OR charwise
        -- charwise = opposite linewise
        return GetPosSelectionRange:new {
            start_line_base1 = dot.line_base1,
            start_col_base1  = dot.col_base1,
            end_line_base1   = v.line_base1,
            end_col_base1    = v.col_base1,
            mode             = mode,
            last_visual_mode = last_visual_mode,
            linewise         = linewise,
            -- PRN add reversed = true/false... if I need to know direction at some point (was dot before v, or v before dot)
        }
    else
        return GetPosSelectionRange:new {
            start_line_base1 = v.line_base1,
            start_col_base1  = v.col_base1,
            end_line_base1   = dot.line_base1,
            end_col_base1    = dot.col_base1,
            mode             = mode,
            last_visual_mode = last_visual_mode,
            linewise         = linewise,
        }
    end
end

---Returns the current selection in 1‑indexed line/column coordinates.
---The order is always start → end regardless of cursor direction.
---@return GetPosSelectionRange
function GetPos.last_selection()
    local lt = getpos_only_line_and_column("'<")
    local gt = getpos_only_line_and_column("'>")

    local mode = vim.fn.mode()
    local last_visual_mode = vim.fn.visualmode()
    local linewise = mode == "V" or (mode ~= "v" and last_visual_mode == "V")
    return GetPosSelectionRange:new {
        start_line_base1 = lt.line_base1,
        start_col_base1 = lt.col_base1,
        end_line_base1 = gt.line_base1,
        end_col_base1 = gt.col_base1,
        mode = mode,
        last_visual_mode = last_visual_mode,
        linewise = linewise,
    }
end

---@return GetPosPosition
function GetPos.last_line_of_buffer()
    return getpos_only_line_and_column("$")
end

---@return GetPosPosition
function GetPos.last_visible_line()
    return getpos_only_line_and_column("w$")
end

---@return GetPosPosition
function GetPos.first_visible_line()
    return getpos_only_line_and_column("w0")
end

return GetPos
