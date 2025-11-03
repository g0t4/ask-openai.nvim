---@param a number
---@param b number
---@return number
function Adder(a, b)
    return a + b
end

---@class Vector3
---@field x number
---@field y number
---@field z number
local Vector3 = {}

--- Vector3 constructor
---@param x number
---@param y number
---@param z number
---@return Vector3
function Vector3.new(x, y, z)
    local t = { x = x, y = y, z = z }
    setmetatable(t, Vector3)
    return t
end
--- example of no blank line before function comments
---@param a Vector3
---@param b Vector3
---@return Vector3
function Vector3.__add(a, b)
    return Vector3.new(a.x + b.x, a.y + b.y, a.z + b.z)
end

-- unrelated comment (blank line separator)

function Subtract(a, b)
    return a - b
end

-- unrelated comment (blank line separator)

---@return number
function Multiply(a, b)
    return a * b
end
