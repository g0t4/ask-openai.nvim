---@class Fold
---@field start_line_base1 number
---@field end_line_base1 number
local Fold = {}

---@param start_line_base1
---@param end_line_base1
---@return Fold
function Fold:new(start_line_base1, end_line_base1)
    -- ensure the Fold class can be used as a prototype
    local obj = setmetatable({}, { __index = Fold, __tostring = Fold.__tostring })
    obj.start_line_base1 = start_line_base1
    obj.end_line_base1 = end_line_base1
    return obj
end

function Fold.__tostring(self)
    return string.format("Fold(%d-%d)", self.start_line_base1, self.end_line_base1)
end

return Fold
