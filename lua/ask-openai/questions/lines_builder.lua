---@class LinesBuilder
---@field turn_lines string[]
---@field marks table[]
local LinesBuilder = {}
LinesBuilder.__index = LinesBuilder

---@return LinesBuilder
function LinesBuilder:new()
    local self = setmetatable({
        turn_lines = {},
        marks = {}
    }, LinesBuilder)
    return self
end

---@param hl_group string
function LinesBuilder:mark_next_line(hl_group)
    local start_line_base0 = #self.turn_lines

    table.insert(self.marks, {
        start_line_base0 = start_line_base0,
        start_col_base0 = 0,
        end_line_base0 = start_line_base0 + 1,
        end_col_base0 = 0,
        hl_group = hl_group
    })
end

---@param role string
function LinesBuilder:add_role(role)
    self:mark_next_line(role == "user" and "AskUserRole" or "AskAssistantRole")
    table.insert(self.turn_lines, role)
end

---@param lines string[]
function LinesBuilder:add_lines_marked(lines, hl_group)
    local start_line_base0 = #self.turn_lines
    local mark = {
        start_line_base0 = start_line_base0, -- base0 b/c next line is the marked one (thus not yet in line count)
        start_col_base0 = 0,
        end_line_base0 = start_line_base0 + #lines, -- IIAC I want end exclusive
        end_col_base0 = 0, -- or, #lines[#lines], to stop on last line (have to -1 on end line too)
        hl_group = hl_group
    }
    table.insert(self.marks, mark)
    vim.list_extend(self.turn_lines, lines)
end

return LinesBuilder
