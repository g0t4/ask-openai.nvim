---@type string[]
local chunks = {}
for i = 1, 50 do
    chunks[i] = "chunk_" .. i
end
local expected_length = 0
local expected_result = ""
for _, chunk in ipairs(chunks) do
    expected_length = expected_length + #chunk
    expected_result = expected_result .. chunk
end

describe("string concatenation vs luajit buffer benchmark", function()
    it("concatenates 100 chunks using .. operator", function()
        local start = vim.uv.hrtime()
        local total = ""
        for _, chunk in ipairs(chunks) do
            total = total .. chunk
        end
        local elapsed_ns = vim.uv.hrtime() - start
        print("concat elapsed ns:", elapsed_ns)
        print("total len:", #total)
        assert.equals(expected_length, #total)
        assert.equals(expected_result, total)
    end)

    it("concatenates 100 chunks using luajit string.buffer", function()
        local start = vim.uv.hrtime()
        local buffer = require("string.buffer").new()
        for _, chunk in ipairs(chunks) do
            buffer:put(chunk)
        end
        local total = buffer:tostring()
        local elapsed_ns = vim.uv.hrtime() - start
        print("buffer elapsed ns:", elapsed_ns)
        print("total len:", #total)
        assert.equals(expected_length, #total)
        assert.equals(expected_result, total)
    end)
end)
