local log = require("ask-openai.logs.logger").predictions()
local files = require("ask-openai.helpers.files")

-- FYI client recommendations:
--  https://agentskills.io/client-implementation/adding-skills-support
-- ~/.agents/skills
-- TODO per repo/project skills

local M = {}

-- Cache of skill name -> absolute path of the skill markdown file
M._skill_paths = {}
-- Cache of skill name -> skill md contents
M._skill_content_cache = {}

--- The content is cached after the first read.
---@param name string The name of the skill
---@return string|nil The skill contents after stripping HTML comments and YAML front‑matter,
---                or nil if the skill cannot be found.
function M.load_skill(name)
    if not name or name == "" then
        error("Skill name is required for load_skill")
    end

    if M._skill_content_cache[name] then
        return M._skill_content_cache[name]
    end

    if not M._skill_paths[name] then
        -- Populate paths (TODO I don't like this.. rename get_skill_commands or split out some functionality)
        M.get_skill_commands()
    end

    local path = M._skill_paths[name]
    if not path or vim.fn.filereadable(path) == 0 then
        return nil
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

    M._skill_content_cache[name] = content
    return content
end

M.cached_skill_commands = nil
--- List of slash commands for skills (cached after first load)
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

        -- Also load markdown files directly under the skills directory.
        local entries = files.list_entries(skills_path)
        for _, entry in ipairs(entries) do
            if entry.type == "file" and entry.name:match("%.md$") then
                local base = entry.name:gsub("%.md$", "")
                -- FYI this means directory wins over standalone markdown file
                if M._skill_paths[base] then
                    vim.notify(string.format(
                        "Skill name collision: '%s' already registered from directory %s; ignoring standalone %s",
                        base,
                        M._skill_paths[base],
                        skills_path .. "/" .. entry.name
                    ), vim.log.levels.WARN)
                else
                    M._skill_paths[base] = skills_path .. "/" .. entry.name
                    table.insert(names, base)
                end
            end
        end
    end
    M.cached_skill_commands = names
    return names
end

return M
