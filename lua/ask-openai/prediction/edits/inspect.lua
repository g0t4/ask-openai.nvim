function get_parser()
    local bufnr = vim.api.nvim_get_current_buf()
    local parser = vim.treesitter.get_parser(bufnr)
    return parser
end

-- FYI nvim-treesitter's `ts_utils` has helpers like ts_utils.get_node_at_cursor()
function get_node_at_cursor()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    return vim.treesitter.get_node({
        bufnr = 0,
        pos = { row - 1, col }
    })
end

function print_node(node)
    print(string.format("Node: %s", node:type()))
    -- btw `:h TSNode` => `:h TSNode:type`
end
