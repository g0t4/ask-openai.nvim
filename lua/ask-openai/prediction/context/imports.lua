local messages = require("devtools.messages")
local require_parser = require("devtools.ts.require_parser")

local M = {}

function M.get_imports()
    require_parser.get_static_requires_lua()
    --TODO use them! i.e. get symbols for them from coc
end

-- FYI IDEAS:
-- include public surface of imported modules
-- also need to handle table assignments and local function assignments
-- also need to look at modules that are imported
-- keep a cache of most imported modules too?
--  and include their public methods?
--  heck could look for most used methods too?
--   => i.e. devtools.messages

return M
