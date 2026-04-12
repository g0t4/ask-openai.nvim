local log = require("ask-openai.logs.logger").predictions()
local files = require("ask-openai.helpers.files")

-- FYI client recommendations:
--  https://agentskills.io/client-implementation/adding-skills-support
-- ~/.agents/skills
-- TODO per repo/project skills

local M = {}
function M.load_skill()
    -- TODO => FYI have the path tracked by get_skill_commands cache of values so when it is time to load you don't have to find it
    --
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
    local commands = {}
    if vim.fn.isdirectory(skills_path) == 1 then
        -- Use helper to list sub‑directories only.
        local dir_names = files.list_directories(skills_path)
        for _, name in ipairs(dir_names) do
            table.insert(commands, "/" .. name)
        end
    end
    M.cached_skill_commands = commands
    return commands
end

return M
