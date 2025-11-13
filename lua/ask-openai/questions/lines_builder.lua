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
    table.insert(self.marks, {
        start_line_base0 = #self.turn_lines,
        start_col_base0 = 0,
        hl_group = hl_group
    })
end

---@param role string
function LinesBuilder:add_role(role)
    self:mark_next_line(role == "user" and "AskUserRole" or "AskAssistantRole")
    table.insert(self.turn_lines, role)
end

return LinesBuilder
