require("ask-openai.helpers.testing")

local tables = require("ask-openai.helpers.tables")
local should = require("devtools.tests.should")

describe("tables.shallow_copy", function()
    it("returns empty table when given nil", function()
        local result = tables.shallow_copy(nil)
        should.be_same(result, {})
        should.be_equal(true, type(result) == "table")
        should.be_equal(0, #result)
    end)

    it("returns empty table when given empty table", function()
        local empty = {}
        local result = tables.shallow_copy(empty)
        should.be_same(result, {})
        should.be_equal(true, result ~= empty)
    end)

    it("shallow copies a list table", function()
        local list = { "a", "b", "c" }
        local result = tables.shallow_copy(list)
        should.be_equal(3, #result)
        should.be_same(result, list)
    end)

    it("shallow copies a map table", function()
        local map = { name = "Alice", age = 30, active = true }
        local result = tables.shallow_copy(map)
        should.be_equal("Alice", result.name)
        should.be_equal(30, result.age)
        should.be_equal(true, result.active)
        should.be_equal(true, result ~= map)
    end)

    it("shallow copies a mixed table", function()
        local mixed = { "first", key1 = "value1", "second", key2 = "value2" }
        local result = tables.shallow_copy(mixed)
        should.be_equal("first", result[1])
        should.be_equal("value1", result.key1)
        should.be_equal("second", result[2])
        should.be_equal("value2", result.key2)
    end)

    it("does not copy nested tables (shallow behavior)", function()
        local nested = { inner = { x = 1, y = 2 } }
        local result = tables.shallow_copy(nested)
        should.be_equal(1, result.inner.x)
        should.be_equal(true, result.inner == nested.inner)
    end)

    it("copies metatable to result", function()
        local original = { 1, 2, 3 }
        local mt = {
            __index = function(t, k)
                return k * 10
            end,
        }
        setmetatable(original, mt)
        local result = tables.shallow_copy(original)
        should.be_equal(true, getmetatable(result) == mt)
        should.be_equal(true, getmetatable(result) ~= nil)
    end)

    it("preserves metatable when given table has no metatable", function()
        local original = { 1, 2, 3 }
        local result = tables.shallow_copy(original)
        should.be_equal(true, getmetatable(result) == getmetatable(original))
    end)
end)
