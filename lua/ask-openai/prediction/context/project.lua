-- how about a long term, persistent, EXPLICIT set of context..
--  things I copy and say these should always be relevant for this project,
--  maybe start with a file (per project)...  like tags
--  could even aggregate these for dependencies too... like tags (ctags)
local messages = require("devtools.messages")
local files = require("ask-openai.helpers.files")


local M = {}

function M.find_project_context()
    -- assume in repo root for now, only allowed spot
    return ".ask/project.md"
end

---@return ContextItem[]
function M.get_context_items()
    local file_path = M.find_project_context()
    local file_contents = files.read_file_string(file_path)
    if file_contents == nil then
        return {}
    end
    -- PRN add other sources, i.e. a dependency
    return { ContextItem:new(file_contents, file_path) }
end

function M.dump_this()
    local items = M.get_context_items()
    messages.ensure_open()
    for _, item in ipairs(items) do
        messages.header(item.filename)
        messages.append(item.content)
    end
    messages.scroll_back_before_last_append()
end

function M.setup()
    vim.api.nvim_create_user_command("AskDumpProjectContext", M.dump_this, {})
end

return M
