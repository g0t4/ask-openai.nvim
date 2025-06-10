local messages = require("devtools.messages")
local require_parser = require("devtools.ts.require_parser")

local M = {}

function M.get_imports()
    -- require_parser.get_static_requires_lua()
    -- TODO WAIT... can I just find the imports in a file (at the top of the file) and show them when I'm editing a file and w/in its top lines?
    --  take top lines until first blank, up to 10 lines per file?
end

return M
