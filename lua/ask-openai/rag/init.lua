local ts = vim.treesitter
local api = vim.api
local messages = require("devtools.messages")

local function extract_lua_chunks(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local parser = ts.get_parser(bufnr, "lua")
    local tree = parser:parse()[1]
    local root = tree:root()
    local chunks = {}

    -- PRN subdivide longer nodes, into subnodes? OR?
    -- PRN remove comments in some / all cases?

    for node in root:iter_children() do
        local type = node:type()
        -- local include = vim.tbl_contains({
        --     "function_declaration",
        --     "local_variable_declaration",
        --     "assignment_statement",
        --     "if_statement",
        --     "for_statement",
        --     "do_statement"
        -- }, type)

        local start_row, _, end_row, _ = node:range()
        table.insert(chunks, {
            type = type,
            start_line = start_row + 1,
            end_line = end_row + 1,
            text = ts.get_node_text(node, bufnr),
        })
    end

    return chunks
end

local M = {}

function M.setup()
    vim.api.nvim_create_user_command("LuaChunks", function()
        messages.ensure_open()
        local chunks = extract_lua_chunks()
        for _, c in ipairs(chunks) do
            messages.divider()
            messages.append(string.format("[%s] %d-%d:\n%s\n", c.type, c.start_line, c.end_line, c.text))
        end
    end, {})
end

return M
