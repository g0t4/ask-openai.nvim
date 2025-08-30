-- how about a long term, persistent, EXPLICIT set of context..
--  things I copy and say these should always be relevant for this project,
--  maybe start with a file (per project)...  like tags
--  could even aggregate these for dependencies too... like tags (ctags)
local messages = require("devtools.messages")
local files = require("ask-openai.helpers.files")


local M = {}

---@param relative_file_path string
local function context_path(relative_file_path)
    return os.getenv("HOME") .. "/.config/ask-openai/context/" .. relative_file_path
end

function M.ensure_read()
    if M._was_read then
        return
    end

    M._global_context = files.read_file_string(context_path("global.md"))

    local project_file = ".ask/project.md"
    if vim.fn.filereadable(project_file) == 1 then
        M._project_context = files.read_file_string(project_file) -- relative to CWD
    end

    M._filetype_contexts = {}

    local function load_filetype_contexts()
        local dir = context_path("filetypes")
        local scandir = vim.loop.fs_scandir(dir)
        if not scandir then
            -- No filetype directory – nothing to load.
            return
        end

        while true do
            local name, typ = vim.loop.fs_scandir_next(scandir)
            if not name then break end
            if typ == "file" and name:sub(-3) == ".md" then
                local ft = name:sub(1, -4) -- strip ".md"
                local path = context_path("filetypes/" .. name)
                local content = files.read_file_string(path)
                M._filetype_contexts[ft] = content
            end
        end
    end
    load_filetype_contexts()

    M._was_read = true
end

---@return ContextItem[]
function M.get_context_items()
    -- TODO wire up outer logic to pass in filetype (of current file)
    M.ensure_read()
    local contexts = {}
    if M._global_context then
        table.insert(contexts, ContextItem:new(M._global_context, "global.md"))
    end

    local ft = vim.bo.filetype
    if ft and M._filetype_contexts[ft] then
        table.insert(contexts, ContextItem:new(M._filetype_contexts[ft], ft .. ".md"))
    end

    if M._project_context then
        table.insert(contexts, ContextItem:new(M._project_context, "project.md"))
    end

    return contexts
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
