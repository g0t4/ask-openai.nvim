local M = {}

function M.parse_includes(prompt)
    local includes = {
        yanks = false,
        commits = false,
    }
    includes.all = (prompt == nil) or (prompt:find("/all") ~= nil)
    if includes.all then
        includes.yanks = true
        includes.commits = true
    else
        includes.yanks = (prompt:find("/yank") ~= nil)
        includes.commits = (prompt:find("/commits") ~= nil)
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
