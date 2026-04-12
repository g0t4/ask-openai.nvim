local log = require("ask-openai.logs.logger").predictions()
local skills = require("ask-openai.frontends.skills")
---@class ParseIncludesResult
---@field all boolean
---@field yanks boolean
---@field commits boolean
---@field current_file boolean
---@field open_files boolean
---@field ctags? boolean
---@field matching_ctags? boolean
---@field norag? boolean
---@field project? boolean
---@field git_diff? boolean
---@field cleaned_prompt string
---@field use_tools? boolean
---@field apply_template_only? boolean
---@field include_selection? boolean
---@field top_k? integer
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

---@param prompt string
---@return integer?, string
local function extract_top_k(prompt)
    -- Extract /k=<number> pattern (e.g., /k=10)
    local top_k = prompt:match("/k=(%d+)")
    if top_k then
        top_k = tonumber(top_k)
        -- Clean the /k=<number> from the prompt
        prompt = prompt:gsub("%s*/k=%d+%s*", " ")
        prompt = prompt:gsub("^/k=%d+%s*", "")
        prompt = prompt:gsub("%s*/k=%d+$", "")
    end
    return top_k, prompt
end

-- expose the slash commands list publicly for reuse elsewhere
M.slash_commands = {
    YANKS         = "/yanks",
    ALL           = "/all",
    COMMITS       = "/commits",
    FILE          = "/file",
    OPEN_FILES    = "/WIP_open_files",
    TOOLS         = "/tools",
    SELECTION     = "/selection",
    TEMPLATE_ONLY = "/WIP_template",
    NORAG         = "/norag",
    READONLY      = "/readonly",
}

--- Completion function for slash commands used by user commands.
-- Returns a list of completions matching the lead entered.
---@param arglead string The current argument lead typed by the user.
---@param cmdline string The full command line.
---@param cursorpos number The cursor position.
---@return string[] List of matching completions.
function M.SlashCommandCompletion(arglead, cmdline, cursorpos)
    local result = {}
    local escaped = vim.pesc(arglead)
    for _, cmd in pairs(M.slash_commands) do
        if cmd:find('^' .. escaped) then
            table.insert(result, cmd)
        end
    end

    -- * merge skill prompts
    -- FYI first load will happen on first completion, s/b fine for slight delay
    for _, cmd in ipairs(skills.get_skill_commands()) do
        if cmd:find('^' .. escaped) then
            table.insert(result, "/" .. cmd)
        end
    end
    return result
end

---@param prompt? string
---@return ParseIncludesResult
function M.parse_includes(prompt)
    prompt = prompt or ""

    -- Extract /k=<number> first, before other processing
    local top_k, prompt_without_k = extract_top_k(prompt)
    prompt = prompt_without_k

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
        all = (prompt == "") or has(M.slash_commands.ALL),
        yanks = has(M.slash_commands.YANKS),
        commits = has(M.slash_commands.COMMITS),
        current_file = has(M.slash_commands.FILE),
        open_files = has(M.slash_commands.OPEN_FILES),
        use_tools = has(M.slash_commands.TOOLS),
        readonly = has(M.slash_commands.READONLY),
        apply_template_only = has(M.slash_commands.TEMPLATE_ONLY),
        include_selection = has(M.slash_commands.SELECTION),
        top_k = top_k,
        cleaned_prompt = prompt,
        norag = has(M.slash_commands.NORAG),
    }

    if includes.all then
        includes.yanks = true
        includes.commits = true
        includes.current_file = true
        includes.open_files = true
        -- ? do I want all to include tools/selection too? for now leave them off (all doesn't have to mean every slash command)
    end

    -- Clean built‑in slash commands from the prompt
    for _, k in ipairs(M.slash_commands) do
        includes.cleaned_prompt = clean_prompt(includes.cleaned_prompt, k)
    end

    -- Process skill slash commands: only if the skill command is present
    local skill_contents = {}
    for _, skill_name in ipairs(skills.get_skill_commands()) do
        local cmd = "/" .. skill_name
        -- Detect presence of the skill command using the same pattern logic as `has`
        local found = includes.cleaned_prompt:find("%W" .. cmd .. "%W")
        found = found or includes.cleaned_prompt:find("^" .. cmd .. "%W")
        found = found or includes.cleaned_prompt:find("%W" .. cmd .. "$")
        if found then
            -- Remove the skill reference from the prompt
            includes.cleaned_prompt = clean_prompt(includes.cleaned_prompt, cmd)
            -- Load and store the skill content for later appending
            local content = skills.load_skill(skill_name)
            if content then
                table.insert(skill_contents, content)
            end
        end
    end
    if #skill_contents > 0 then
        includes.cleaned_prompt = includes.cleaned_prompt .. "\n" .. table.concat(skill_contents, "\n")
    end

    -- log:info("includes", vim.inspect(includes))
    return includes
end

return M
