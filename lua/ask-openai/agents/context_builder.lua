local files = require("ask-openai.helpers.files")
local log = require("devtools.logs.logger").universal()

local M = {}

--- Build git-aware context text for agent prompts.
--- Returns a string to be injected into INSERT_CWD.
---@param cwd string
---@param repo_root string|nil
---@return string
function M.build_git_context(cwd, repo_root)
    local cwd_text = "Current directory: " .. cwd

    if repo_root == nil then
        log:info("not in a repo, suggesting to agent to stay within workdir", vim.log.levels.WARN)
        cwd_text = cwd_text .. "\nyou are not in a git repo, please only make changes in the workdir unless requested"
        return cwd_text
    end

    -- repo exists
    local repo_name = repo_root:match("([^/]+)$") or repo_root
    cwd_text = cwd_text .. "\nRepo: " .. repo_name .. " (root: " .. repo_root .. ")"

    if repo_root ~= cwd then
        vim.notify("NESTED REPO", vim.log.levels.WARN)
        cwd_text = cwd_text .. "\nRepository root: " .. repo_root
        local relative_path = cwd:sub(#repo_root + 2)
        local depth = 0
        for _ in string.gmatch(relative_path, "[^/]+") do
            depth = depth + 1
        end
        if depth > 0 then
            local rel = ("../"):rep(depth)
            cwd_text = cwd_text .. "\nYou are " .. depth .. " levels deep, so you need " .. rel .. " to build relative paths from repo root."
        else
            vim.notify("You aren't in repo root and yet the calculation for number of levels deep returned 0???, check logic for levels deep warning", vim.log.levels.WARN)
        end
    end

    -- dirty check
    local git_status = vim.fn.system("git -C " .. repo_root .. " status --porcelain")
    local repo_is_dirty = git_status ~= ""
    if repo_is_dirty then
        vim.notify("DIRTY REPO", vim.log.levels.WARN)
        cwd_text = cwd_text .. "\nDirty repo at start"
    end

    return cwd_text
end

return M
