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
---@field rendered_prompt string
---@field use_tools? boolean
---@field apply_template_only? boolean
---@field include_selection? boolean
---@field top_k? integer
local M = {}

---@param prompt string
---@param command string
---@return string
local function strip_slash_command_from_prompt(prompt, command)
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

    -- Process skill slash commands first: detect skill references, load their content,
    -- resolve any built‑in slash commands inside the skill content, and clean the
    -- skill content before injecting it.
    local raw_skill_contents = {}
    local rendered_prompt = prompt
    for _, skill_name in pairs(skills.get_skill_commands()) do
        local cmd = "/" .. skill_name
        -- Detect presence of the skill command using the same pattern logic as `has`
        local found = rendered_prompt:find("%W" .. cmd .. "%W")
        found = found or rendered_prompt:find("^" .. cmd .. "%W")
        found = found or rendered_prompt:find("%W" .. cmd .. "$")
        if found then
            -- Remove the skill reference from the prompt
            rendered_prompt = strip_slash_command_from_prompt(rendered_prompt, cmd)
            -- Load the skill content for later processing
            local content = skills.load_skill(skill_name)
            if content then
                table.insert(raw_skill_contents, content)
            end
        end
    end

    -- Append the cleaned skill contents.
    if #raw_skill_contents > 0 then
        rendered_prompt = rendered_prompt .. "\n" .. table.concat(raw_skill_contents, "\n")
    end

    local function has_in(what, command)
        -- in middle, between whitespace
        local found = what:find("%W(" .. command .. ")%W")
        -- start of string, with whitespace after
        found = found or what:find("^" .. command .. "%W")
        -- end of string, with whitespace before
        found = found or what:find("%W" .. command .. "$")
        return found ~= nil
    end
    local function prompt_has(command)
        return has_in(rendered_prompt, command)
    end

    ---@type ParseIncludesResult
    local includes = {
        all = (prompt == "") or prompt_has(M.slash_commands.ALL),
        yanks = prompt_has(M.slash_commands.YANKS),
        commits = prompt_has(M.slash_commands.COMMITS),
        current_file = prompt_has(M.slash_commands.FILE),
        open_files = prompt_has(M.slash_commands.OPEN_FILES),
        use_tools = prompt_has(M.slash_commands.TOOLS),
        readonly = prompt_has(M.slash_commands.READONLY),
        apply_template_only = prompt_has(M.slash_commands.TEMPLATE_ONLY),
        include_selection = prompt_has(M.slash_commands.SELECTION),
        top_k = top_k,
        rendered_prompt = "",
        norag = prompt_has(M.slash_commands.NORAG),
    }

    -- After processing skill content, propagate the effect of /all if it was discovered.
    if includes.all then
        includes.yanks = true
        includes.commits = true
        includes.current_file = true
        includes.open_files = true
    end

    for _, k in pairs(M.slash_commands) do
        rendered_prompt = strip_slash_command_from_prompt(rendered_prompt, k)
    end

    includes.rendered_prompt = rendered_prompt
    -- log:info("includes", vim.inspect(includes))
    return includes
end

return M
