local log = require("ask-openai.logs.logger").predictions()
local files = require("ask-openai.helpers.files")

-- FYI client recommendations:
--  https://agentskills.io/client-implementation/adding-skills-support
-- ~/.agents/skills
-- TODO per repo/project skills

local M = {}

-- Cache mapping skill name -> absolute path of the SKILL.md file
M._skill_paths = {}
-- Cache for loaded skill file contents (keyed by absolute path)
M._skill_content_cache = {}

--- Load and return the processed content of a skill.
--- The content is cached after the first read.
---@param name string The name of the skill (directory name under ~/.agents/skills)
---@return string|nil The skill content after stripping HTML comments and YAML front‑matter,
---                or nil if the skill cannot be found.
function M.load_skill(name)
    if not name or name == "" then
        error("Skill name is required for load_skill")
    end

    -- Ensure the skill path map is populated.
    if not M._skill_paths[name] then
        -- Populate the skill map (also populates cached_skill_commands)
        M.get_skill_commands()
    end

    local path = M._skill_paths[name]
    if not path or vim.fn.filereadable(path) == 0 then
        return nil
    end

    -- Return cached content if available.
    if M._skill_content_cache[path] then
        return M._skill_content_cache[path]
    end

    local raw = files.read_text(path)
    if not raw then
        return nil
    end

    -- Strip HTML comments: <!-- comment --> (non‑greedy)
    local without_comments = raw:gsub("<!--.-?-->", "")
    -- Remove YAML front‑matter delimited by triple dashes at the start of the file.
    local content = without_comments
    if content:match("^%-%-%-") then
        -- Remove everything from the opening '---' to the next closing '---' line.
        content = content:gsub("^%-%-%-.-%-%-%-\n?", "")
    end
    -- Trim leading/trailing whitespace for cleanliness.
    content = vim.trim(content)

    -- Cache and return.
    M._skill_content_cache[path] = content
    return content
end

M.cached_skill_commands = nil

--- Retrieve slash command entries representing skill directories under
--- `~/.agent/skills`. The result is cached after the first successful read.
---@return string[] List of slash commands (e.g., "/my_skill")
function M.get_skill_commands()
    if M.cached_skill_commands then
        return M.cached_skill_commands
    end

    local skills_path = vim.fn.expand("~/.agents/skills")
    local names = {}
    if vim.fn.isdirectory(skills_path) == 1 then
        -- Use helper to list sub‑directories only.
        local dir_names = files.list_directories(skills_path)
        for _, name in ipairs(dir_names) do
            -- Store the absolute path to the SKILL.md file for later loading.
            M._skill_paths[name] = skills_path .. "/" .. name .. "/SKILL.md"
            table.insert(names, name)
        end
    end
    -- PRN load standalone files too? no need for foo/SKILL.md ???
    M.cached_skill_commands = names
    return names
end

return M
