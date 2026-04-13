-- FYI https://tree-sitter.github.io/tree-sitter/3-syntax-highlighting.html

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

function traverse_tree(node, cb)
    if not node then return end
    cb(node)
    for i = 0, node:named_child_count() - 1 do
        local child = node:named_child(i)
        traverse_tree(child, cb)
    end
end

function get_root_node()
    local parser = get_parser()
    if not parser then return end
    return parser:parse()[1]:root()
end

function find_parent_function(node)
    while node do
        -- todo is method_declaration a thing?
        if node:type() == "function_declaration" or node:type() == "method_declaration" then
            return node
        end
        node = node:parent()
    end
    return nil
end

--
-- local function find_all_functions(bufnr)
--     local parser = vim.treesitter.get_parser(bufnr)
--     local tree = parser:parse()[1]
--     local root = tree:root()
--
--     local query = vim.treesitter.query.parse("lua", [[
--     (function_definition name: (identifier) @func_name)
--   ]])
--
--     for _, match, _ in query:iter_matches(root, bufnr) do
--         for _, node in pairs(match) do
--             print("Function:", get_text(node, bufnr))
--         end
--     end
-- end


function is_inside_function()
    return find_parent_function(get_node_at_cursor()) ~= nil
end

--- use an item's __tostring to represent itself (if available)
-- FYI use vim.inspect for a VERBATIM dump of a table
--- including on tables
function inspect_repr(x)
    -- FYI made to show Fold type, to condense representations when I don't need the table dumped verbatim
    local mt = getmetatable(x)
    if mt and mt.__tostring then
        return tostring(x)
    end
    if type(x) == "table" then
        local copy = {}
        for k, v in pairs(x) do
            -- FYI k will be either an index or a key depending on table type
            local vmt = getmetatable(v)
            if vmt and vmt.__tostring then
                copy[k] = tostring(v)
            else
                copy[k] = v
            end
        end
        return vim.inspect(copy)
    end
    return vim.inspect(x)
end
