local log = require("devtools.logs.logger").universal()
local files = require("ask-openai.helpers.files")

local M = {}

-- Cache of skill name -> absolute path of the skill markdown file
M._skill_paths_by_name = {}
-- Cache of skill name -> skill md contents
M._skill_contents_by_name = {}

---@param raw string
---@return string cleaned
function M.clean_contents(raw)
    local content = raw

    -- Remove YAML front‑matter
    if content:match("^%-%-%-") then
        -- Remove everything from the opening '---' to the next closing '---' line,
        -- and consume any following whitespace (including CRLF line endings).
        content = content:gsub("^%-%-%-.-%-%-%-%s*", "")
    end

    -- strip HTML comments (non‑greedy)
    content = content:gsub("<!--.-?-->", "")

    content = vim.trim(content)
    return content
end

--- The content is cached after the first read.
---@param name string The name of the skill
---@return string|nil The skill contents after stripping HTML comments and YAML front‑matter,
---                or nil if the skill cannot be found.
function M.load_skill(name)
    if not name or name == "" then
        error("skill name is required for load_skill")
    end

    if M._skill_contents_by_name[name] then
        return M._skill_contents_by_name[name]
    end

    if not M._skill_paths_by_name[name] then
        -- Populate paths (TODO I don't like this.. rename get_skill_slash_commands or split out some functionality)
        M.get_skill_slash_commands()
    end

    local path = M._skill_paths_by_name[name]
    if not path or vim.fn.filereadable(path) == 0 then
        log:error(string.format("skill file not found: %s", name))
        return nil
    end

    local raw = files.read_text(path)
    if not raw then
        log:error(string.format("Empty skill %s in %s", name, path))
        return nil
    end

    local content = M.clean_contents(raw)
    M._skill_contents_by_name[name] = content
    return content
end

M.cached_skill_slash_commands = nil

--- Internal loader that populates `M._skill_paths_by_name` and returns the command list.
---@return string[] List of slash commands (e.g., "/my_skill")
local function _load_skill_slash_commands()
    local global_skills_dir = vim.fn.expand("~/.agents/skills")
    local paths = {}
    if vim.fn.isdirectory(global_skills_dir) == 1 then
        -- * global skill directories
        local dir_names = files.list_directories(global_skills_dir)
        for _, name in ipairs(dir_names) do
            paths[name] = global_skills_dir .. "/" .. name .. "/SKILL.md"
        end

        -- * global standalone markdown files
        local entries = files.list_entries(global_skills_dir)
        for _, entry in ipairs(entries) do
            if entry.type == "file" and entry.name:match("%.md$") then
                local skill_name = entry.name:gsub("%.md$", "")
                if paths[skill_name] then
                    vim.notify(string.format(
                        "Skill name collision: '%s' already registered; overriding with global file %s",
                        skill_name,
                        global_skills_dir .. "/" .. entry.name
                    ), vim.log.levels.WARN)
                end
                paths[skill_name] = global_skills_dir .. "/" .. entry.name
            end
        end
    end

    -- * repo‑specific skills: <repo_root>/.agents/local/skills
    local repo_root = files.get_repo_root()
    if not repo_root then
        return paths
    end
    local repo_skills_dir = repo_root .. '/.agents/local/skills'
    if vim.fn.isdirectory(repo_skills_dir) ~= 1 then
        return paths
    end
    -- * repo-specific skill directories
    local dir_names = files.list_directories(repo_skills_dir)
        for _, name in ipairs(dir_names) do
            if paths[name] then
                vim.notify(string.format(
                    "Skill name collision: '%s' already registered; overriding with repo directory %s",
                    name,
                    repo_skills_dir .. '/' .. name
                ), vim.log.levels.WARN)
            end
            paths[name] = repo_skills_dir .. '/' .. name .. '/SKILL.md'
        end

    -- * repo-specific standalone markdown files
    local entries = files.list_entries(repo_skills_dir)
        for _, entry in ipairs(entries) do
            if entry.type == 'file' and entry.name:match('%.md$') then
                local skill_name = entry.name:gsub('%.md$', '')
                if paths[skill_name] then
                    vim.notify(string.format(
                        "Skill name collision: '%s' already registered; overriding with repo file %s",
                        skill_name,
                        repo_skills_dir .. '/' .. entry.name
                    ), vim.log.levels.WARN)
                end
                paths[skill_name] = repo_skills_dir .. '/' .. entry.name
            end
        end
    return paths
end

--- List of slash commands for skills (cached after first load)
---@return string[] List of slash commands (e.g., "/my_skill")
function M.get_skill_slash_commands()
    if M.cached_skill_slash_commands then
        return M.cached_skill_slash_commands
    end
    local paths = _load_skill_slash_commands()
    M._skill_paths_by_name = paths
    local names = vim.tbl_keys(paths)
    M.cached_skill_slash_commands = names
    return names
end

return M
