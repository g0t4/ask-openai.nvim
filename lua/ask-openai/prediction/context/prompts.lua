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

    -- strip /yank et al from prompt
    includes.cleaned_prompt = prompt:gsub("(%W)(/all)%W", "%1")
    includes.cleaned_prompt = includes.cleaned_prompt:gsub("^/all%W", "")
    -- at end with whitespace before:
    includes.cleaned_prompt = includes.cleaned_prompt:gsub("%W/all$", "")



    return includes
end

return M
