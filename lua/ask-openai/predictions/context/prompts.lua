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
    log:info("original prompt:", prompt)
    log:info("      cleaned:", cleaned)
    log:info("      command:", command)
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

    -- Process skill slash commands first: detect skill references, load their content,
    -- resolve any built‑in slash commands inside the skill content, and clean the
    -- skill content before injecting it.
    local raw_skill_contents = {}
    for _, skill_name in pairs(skills.get_skill_commands()) do
        local cmd = "/" .. skill_name
        -- Detect presence of the skill command using the same pattern logic as `has`
        local found = includes.cleaned_prompt:find("%W" .. cmd .. "%W")
        found = found or includes.cleaned_prompt:find("^" .. cmd .. "%W")
        found = found or includes.cleaned_prompt:find("%W" .. cmd .. "$")
        if found then
            -- Remove the skill reference from the prompt
            includes.cleaned_prompt = clean_prompt(includes.cleaned_prompt, cmd)
            -- Load the skill content for later processing
            local content = skills.load_skill(skill_name)
            if content then
                table.insert(raw_skill_contents, content)
            end
        end
    end

    -- Helper to detect a slash command inside an arbitrary string.
    local function has_in(str, command)
        local found = str:find("%W(" .. command .. ")%W")
        found = found or str:find("^" .. command .. "%W")
        found = found or str:find("%W" .. command .. "$")
        return found ~= nil
    end

    -- Mapping from slash command strings to the corresponding includes field.
    local slash_to_field = {
        [M.slash_commands.ALL] = "all",
        [M.slash_commands.YANKS] = "yanks",
        [M.slash_commands.COMMITS] = "commits",
        [M.slash_commands.FILE] = "current_file",
        [M.slash_commands.OPEN_FILES] = "open_files",
        [M.slash_commands.TOOLS] = "use_tools",
        [M.slash_commands.READONLY] = "readonly",
        [M.slash_commands.TEMPLATE_ONLY] = "apply_template_only",
        [M.slash_commands.SELECTION] = "include_selection",
        [M.slash_commands.NORAG] = "norag",
    }

    -- Process each loaded skill content: detect slash commands within it, update includes,
    -- and strip those commands from the content before injection.
    local processed_skill_contents = {}
    for _, content in ipairs(raw_skill_contents) do
        local cleaned = content
        for cmd, field in pairs(slash_to_field) do
            if has_in(content, cmd) then
                includes[field] = true
            end
            cleaned = clean_prompt(cleaned, cmd)
        end
        table.insert(processed_skill_contents, cleaned)
    end

    -- After processing skill content, propagate the effect of /all if it was discovered.
    if includes.all then
        includes.yanks = true
        includes.commits = true
        includes.current_file = true
        includes.open_files = true
    end

    -- Clean built‑in slash commands from the (now) cleaned prompt.
    for _, k in pairs(M.slash_commands) do
        includes.cleaned_prompt = clean_prompt(includes.cleaned_prompt, k)
    end

    -- Append the cleaned skill contents.
    if #processed_skill_contents > 0 then
        includes.cleaned_prompt = includes.cleaned_prompt .. "\n" .. table.concat(processed_skill_contents, "\n")
    end

    -- log:info("includes", vim.inspect(includes))
    return includes
end

return M
