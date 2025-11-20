---@type string[]
local chunks = {}
for i = 1, 200 do
    chunks[i] = "chunk_" .. i
end
local expected_length = 0
local expected_result = ""
for _, chunk in ipairs(chunks) do
    expected_length = expected_length + #chunk
    expected_result = expected_result .. chunk
end

-- FYI DO NOT DO ANYTHING UNTIL YOU KNOW FOR SURE THIS WILL MATTER
--  requirements:
--    need to update extmarks (right now I redraw the entire thing... so on each iteration I need to get the full string - I think that will destroy any buffer advantage... though I could be wrong)
--    for predictions I usually limit to 200 generated tokens... at that size there is not much of a difference.. like worst case ratio is 3:1 concat:buffer (on first iteration)... and it's like 70us vs 25us  so not consequential
--    FYI if I don't need full string each iteration, then yes buffer will make a difference but... I don't have a need to build the entire string then if I do smth token by token to update extmarks (maybe I should be doing that actually!)
-- *** https://luajit.org/ext_buffer.html StringBuffer
describe("string concatenation vs luajit buffer benchmark", function()
    local iterations = 10

    it("concatenates 100 chunks using luajit string.buffer", function()
        local total_elapsed_ns = 0
        for i = 1, iterations do
            local start = vim.uv.hrtime()
            local buffer = require("string.buffer").new()
            local total
            for _, chunk in ipairs(chunks) do
                buffer:put(chunk)
                total = buffer:tostring() -- FYI this is what kills it for using buffer... so unless I get rid of needing the full string on every iteration, I don't think I'll see any benefit in a buffer
            end
            local elapsed_ns = vim.uv.hrtime() - start
            print("buffer iteration:", i, "elapsed ns:", elapsed_ns)
            total_elapsed_ns = total_elapsed_ns + elapsed_ns
            assert.equals(expected_length, #total)
            assert.equals(expected_result, total)
        end
        local avg_elapsed_ns = total_elapsed_ns / iterations
        print("buffer average elapsed ns:", avg_elapsed_ns)
    end)

    it("concatenates 100 chunks using .. operator", function()
        local total_elapsed_ns = 0
        for i = 1, iterations do
            local start = vim.uv.hrtime()
            local total = ""
            for _, chunk in ipairs(chunks) do
                total = total .. chunk
            end
            local elapsed_ns = vim.uv.hrtime() - start
            print("concat iteration:", i, "elapsed ns:", elapsed_ns)
            total_elapsed_ns = total_elapsed_ns + elapsed_ns
            assert.equals(expected_length, #total)
            assert.equals(expected_result, total)
        end
        local avg_elapsed_ns = total_elapsed_ns / iterations
        print("concat average elapsed ns:", avg_elapsed_ns)
    end)
end)
