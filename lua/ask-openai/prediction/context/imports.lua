local messages = require("devtools.messages")
local require_parser = require("devtools.ts.require_parser")

local M = {}

function M.get_imports()
    -- TODO WAIT... can I just find the imports in a file (at the top of the file)
    -- and show them when I'm editing a file and w/in its top lines?
    -- maybe for open files only? or buffer files?
    -- and/or take top lines until first blank, up to 10 lines per file?

    -- FOR EXAMPLE:
    --  local log = require("ask-openai.logs.logger").predictions()
    -- FYI could just grep files and find a way to flag them as parsed until changed
    -- add some thing like ctags to do this, maybe even use ctags plugins/extension?
end

return M
