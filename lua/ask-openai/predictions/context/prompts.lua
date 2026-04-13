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
---@return integer?, string
function M.strip_patterns_from_prompt(prompt)
    -- i.e. /k=10
    local top_k = nil
    local function strip(match)
        top_k = tonumber(match)
        return "" -- strip
    end
    -- FYI CANNOT HAVE /k= butted up against ANYTHING but whitespace
    prompt = prompt:gsub("^%s*/k=(%d+)%s*", strip) -- start (specific)
    prompt = prompt:gsub("%s*/k=(%d+)%s*$", strip) -- end (specific)
    prompt = prompt:gsub("%s*/k=(%d+)%s*", function(match)
        top_k = tonumber(match)
        return " " -- replace w/ one space
    end) -- middle matches (spaces on both sides)
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

    -- * static slash commands
    for _, cmd in pairs(M.slash_commands) do
        if cmd:find('^' .. escaped) then
            table.insert(result, cmd)
        end
    end

    -- * add skill prompts
    -- FYI first load will happen on first completion, s/b fine for slight delay
    for _, cmd in ipairs(skills.get_skill_commands()) do
        if cmd:find('^' .. escaped) then
            table.insert(result, "/" .. cmd)
        end
    end
    return result
end

---@param prompt string
---@param command string
---@return boolean, string
local function strip_slash_command_from_prompt(prompt, command)
    local cleaned = prompt:gsub("^%s*" .. command .. "%s", "") -- start (optional whitespace before)

    cleaned = cleaned:gsub("%s" .. command .. "%s*$", "") -- end (optional whitespace after, until end)

    cleaned = cleaned:gsub("(%s+)(" .. command .. ")%s+", "%1") -- middle matches (whitespace on both sides)
    -- %1 => keep capture 1 (space before)

    -- -- especially useful to see changes when recursive rendering
    if cleaned ~= prompt then
        log:info("original prompt: `" .. prompt .. "`")
        log:info("      cleaned: `" .. cleaned .. "`")
        log:info("      command: `" .. command .. "`")
    end
    return cleaned ~= prompt, cleaned
end

---@param prompt? string
---@return ParseIncludesResult
function M.render(prompt)
    prompt = prompt or ""

    -- * inject skills first
    local skill_contents = {}
    local rendered_prompt = prompt
    for _, skill_name in pairs(skills.get_skill_commands()) do
        local cmd = "/" .. skill_name
        local found, rendered_prompt = strip_slash_command_from_prompt(rendered_prompt, cmd)
        if found then
            local content = skills.load_skill(skill_name)
            if content then
                table.insert(skill_contents, content)
            end
        end
    end
    if #skill_contents > 0 then
        rendered_prompt = rendered_prompt .. "\n" .. table.concat(skill_contents, "\n")
    end

    -- * detect pattern based fields
    local top_k, rendered_prompt = M.strip_patterns_from_prompt(rendered_prompt)

    ---@type table<string, string>
    M.slash_command_to_field = {
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

    ---@type ParseIncludesResult
    local includes = {
        -- patterns:
        top_k = top_k,
    }
    -- * detect static commands
    for _, command in pairs(M.slash_commands) do
        local found
        found, rendered_prompt = strip_slash_command_from_prompt(rendered_prompt, command)
        local field = M.slash_command_to_field[command]
        if field then
            includes[field] = found
        else
            vim.notify("missing field for slash command: " .. command, vim.log.levels.ERROR)
            log:error("missing field for slash command: " .. command)
        end
    end

    -- propagate the effect of /all
    if includes.all then
        -- defaults for /all:
        includes.yanks = true
        includes.commits = true
        includes.current_file = true
        includes.open_files = true
    end

    includes.rendered_prompt = rendered_prompt
    -- log:info("includes", vim.inspect(includes))
    return includes
end

return M
