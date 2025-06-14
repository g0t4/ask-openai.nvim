local M = {}

local function clean_prompt(prompt, command)
    -- in middle, between whitespace
    local cleaned = prompt:gsub("(%W)(" .. command .. ")%W", "%1")
    -- start of string, with whitespace after
    cleaned = cleaned:gsub("^" .. command .. "%W", "")
    -- end of string, with whitespace before
    cleaned = cleaned:gsub("%W" .. command .. "$", "")
    return cleaned
end

function M.parse_includes(prompt)
    prompt = prompt or ""

    local function has(command)
        -- in middle, between whitespace
        local found = prompt:find("%W(" .. command .. ")%W")
        -- start of string, with whitespace after
        found = found or prompt:find("^" .. command .. "%W")
        -- end of string, with whitespace before
        found = found or prompt:find("%W" .. command .. "$")
        return found ~= nil
    end

    local includes = {
        all = (prompt == "") or has("/all"),
        yanks = true,
        commits = true,
    }
    if not includes.all then
        includes.yanks = has("/yanks")
        includes.commits = has("/commits")
    end

    local cleaned = prompt
    for _, k in ipairs({ "/yanks", "/all", "/commits" }) do
        cleaned = clean_prompt(cleaned, k)
    end
    includes.cleaned_prompt = cleaned

    return includes
end

return M
