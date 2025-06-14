local M = {}

function M.parse_includes(prompt)
    function has(command)
        local found = prompt:find(command)
        return found ~= nil
    end

    local includes = {
        yanks = false,
        commits = false,
    }
    includes.all = (prompt == nil) or has("/all")
    if includes.all then
        includes.yanks = true
        includes.commits = true
    else
        includes.yanks = has("/yanks")
        includes.commits = has("/commits")
    end

    function clean_prompt(prompt, command)
        local cleaned = prompt:gsub("(%W)(" .. command .. ")%W", "%1")
        cleaned = cleaned:gsub("^" .. command .. "%W", "")
        cleaned = cleaned:gsub("%W" .. command .. "$", "")
        return cleaned
    end

    includes.cleaned_prompt = clean_prompt(prompt, "/all")


    return includes
end

return M
