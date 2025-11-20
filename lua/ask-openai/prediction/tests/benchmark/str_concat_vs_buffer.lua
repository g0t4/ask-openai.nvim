describe("string concatenation vs luajit buffer benchmark", function()
    ---@type string[]
    local chunks = {}
    for i = 1, 200 do
        chunks[i] = "chunk_" .. i
    end

    it("concatenates 100 chunks using .. operator", function()
        local start = vim.uv.hrtime()
        local total = ""
        for _, chunk in ipairs(chunks) do
            total = total .. chunk
        end
        local elapsed_ns = vim.uv.hrtime() - start
        print("concat elapsed ns:", elapsed_ns)
    end)

    it("concatenates 100 chunks using luajit string.buffer", function()
        local buffer = require("string.buffer").new()
        local start = vim.uv.hrtime()
        for _, chunk in ipairs(chunks) do
            buffer:put(chunk)
        end
        local total = buffer:tostring()
        local elapsed_ns = vim.uv.hrtime() - start
        print("buffer elapsed ns:", elapsed_ns)
    end)
end)
