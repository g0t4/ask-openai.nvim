local M = {}

function M.add(a, b)
    return a + b
end

function M.sub(a, b)
    return a - b
end

function M.mul(a, b)
    return a * b
end

function M.div(a, b)
    if b == 0 then
        error("Cannot divide by zero")
    end
    return a / b
end

-- Adding support for modulo operation
function M.mod(a, b)
    return a % b
end

-- Adding support for exponentiation (power of one number to another)
function M.pow(a, b)
    return a ^ b
end

-- Support for square root function
function M.sqrt(x)
    if x < 0 then
        error("Cannot compute the square root of negative numbers.")
    end
    return math.sqrt(x)
end

-- Support for absolute value functions
function M.abs(num)
    return math.abs(num)
end

-- Support for maximum and minimum values function
function M.max(a, b)
    return math.max(a, b)
end

function M.min(a, b) return math.min(a, b) end

-- Note: This Lua module provides basic arithmeti0c





return M
