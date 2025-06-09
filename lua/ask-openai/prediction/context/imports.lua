local messages = require("devtools.messages")
local dev_ts = require("devtools.ts")

local M = {}

function M.get_imports()
    dev_ts.get_static_requires_lua()
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
