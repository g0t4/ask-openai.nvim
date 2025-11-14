---@class ParseIncludesResult
---@field all boolean
---@field yanks boolean
---@field commits boolean
---@field current_file boolean
---@field open_files boolean
---@field cleaned_prompt string

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
        cleaned_prompt = "",
    }

    if includes.all then
        includes.yanks = true
        includes.commits = true
        includes.current_file = true
        includes.open_files = true
    end

    local cleaned = prompt
    for _, k in ipairs({ "/yanks", "/all", "/commits", "/file", "/files", }) do
        cleaned = clean_prompt(cleaned, k)
    end
    includes.cleaned_prompt = cleaned

    return includes
end

return M
