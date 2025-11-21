local assert = require 'luassert'
require("ask-openai.helpers.test_setup").modify_package_path()
require("ask-openai.helpers.buffer_testing")



it("benchmark setpos vs nvim_win_set_cursor", function()
    -- ***! TLDR difference is negligible at 490ns vs 150ns... only matters if calling alot in a tight loop
    -- setting marks slows down setpos.. vs nvim_win_set_cursor (IIUC that is one difference)
    --  only setpos triggers events?

    local bufnr = new_buffer_with_lines({ "line 1", "line 2" })

    local iterations = 1e6
    local win = 0

    -- Benchmark nvim_win_set_cursor
    local start = vim.loop.hrtime()
    for i = 1, iterations do
        vim.api.nvim_win_set_cursor(win, { 1, 0 })
    end
    local elapsed_cursor_ns = vim.loop.hrtime() - start
    local elapsed_cursor_ms = (elapsed_cursor_ns) / 1e6
    local elapsed_cursor_ns_per_call = elapsed_cursor_ns / iterations

    -- Benchmark setpos(".")
    start = vim.loop.hrtime()
    for i = 1, iterations do
        vim.fn.setpos('.', { bufnr, 1, 1, 0 })
    end
    local elapsed_setpos_ns = vim.loop.hrtime() - start
    local elapsed_setpos_ms = (elapsed_setpos_ns) / 1e6
    local elapsed_setpos_ns_per_call = elapsed_setpos_ns / iterations

    print(string.format("nvim_win_set_cursor:\n   total: %.2f ms", elapsed_cursor_ms))
    print(string.format("   per call: %d ns", elapsed_cursor_ns_per_call))
    print(string.format("setpos:\n   total: %.2f ms", elapsed_setpos_ms))
    print(string.format("   per call: %d ns", elapsed_setpos_ns_per_call))
end)
