---@class ParseIncludesResult
---@field all boolean
---@field yanks boolean
---@field commits boolean
---@field current_file boolean
---@field open_files boolean
---@field ctags? boolean
---@field matching_ctags? boolean
---@field project? boolean
---@field git_diff? boolean
---@field cleaned_prompt string
---@field use_tools? boolean
---@field include_selection? boolean
local M = {}

---@param prompt string
---@param command string
---@return string
local function clean_prompt(prompt, command)
    -- in middle, between whitespace
    local cleaned = prompt:gsub("(%W)(" .. command .. ")%W", "%1")
    -- start of string, with whitespace after
    cleaned = cleaned:gsub("^" .. command .. "%W", "")
    -- end of string, with whitespace before
    cleaned = cleaned:gsub("%W" .. command .. "$", "")
    return cleaned
end

---@param prompt? string
---@return ParseIncludesResult
function M.parse_includes(prompt)
    prompt = prompt or ""

    ---@param command string
    ---@return boolean
    local function has(command)
        -- in middle, between whitespace
        local found = prompt:find("%W(" .. command .. ")%W")
        -- start of string, with whitespace after
        found = found or prompt:find("^" .. command .. "%W")
        -- end of string, with whitespace before
        found = found or prompt:find("%W" .. command .. "$")
        return found ~= nil
    end

    ---@type ParseIncludesResult
    local includes = {
        all = (prompt == "") or has("/all"),
        yanks = has("/yanks"),
        commits = has("/commits"),
        current_file = has("/file"),
        open_files = has("/files"),
        use_tools = has("/tools"),
        include_selection = has("/selection"),
        cleaned_prompt = prompt,
    }

    if includes.all then
        includes.yanks = true
        includes.commits = true
        includes.current_file = true
        includes.open_files = true
        -- ? do I want all to include tools/selection too? for now leave them off (all doesn't have to mean every slash command)
    end

    local slash_commands = { "/yanks", "/all", "/commits", "/file", "/files", "/tools", "/selection", }
    for _, k in ipairs(slash_commands) do
        includes.cleaned_prompt = clean_prompt(includes.cleaned_prompt, k)
    end

    return includes
end

return M
