local messages = require("devtools.messages")
-- (chunk ; [0, 0] - [26, 0]
--   local_declaration: (variable_declaration ; [0, 0] - [0, 45]
--     (assignment_statement ; [0, 6] - [0, 45]
--       (variable_list ; [0, 6] - [0, 14]
--         name: (identifier)) ; [0, 6] - [0, 14]
--       (expression_list ; [0, 17] - [0, 45]
--         value: (function_call ; [0, 17] - [0, 45]
--           name: (identifier) ; [0, 17] - [0, 24]
--           arguments: (arguments ; [0, 24] - [0, 45]
--             (string ; [0, 25] - [0, 44]
--               content: (string_content))))))) ; [0, 26] - [0, 43]

-- TODO include public surface of imported modules
-- :imported modules

local M = {}

function M.get_imports()
    messages.ensure_open()
    local root = vim.treesitter.get_parser(0) -- TODO later pass filename too for deps of deps?
    local tree = root:parse()
    local root_node = tree[1]:root()
    local result = {}
    -- go with top level imports only, inside a local_declaration
    for _, child in root_node:iter_children() do
        -- if child:type() == "expression_list" then
        messages.append(_:type())
        -- end
    end
    return result
end

-- TODO keep a cache of most imported modules too?
--  and include their public methods?
--  heck could look for most used methods too?
--   => i.e. devtools.messages

return M
