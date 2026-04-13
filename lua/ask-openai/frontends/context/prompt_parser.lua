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
---@field readonly? boolean
---@field reasoning_low? boolean
---@field reasoning_medium? boolean
---@field reasoning_high? boolean
---@field reasoning_none? boolean
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
    YANKS            = "/yanks",
    ALL              = "/all",
    COMMITS          = "/commits",
    FILE             = "/file",
    OPEN_FILES       = "/WIP_open_files",
    TOOLS            = "/tools",
    SELECTION        = "/selection",
    TEMPLATE_ONLY    = "/WIP_template",
    NORAG            = "/norag",
    READONLY         = "/readonly",

    -- reasoning levels
    REASONING_LOW    = "/low",
    REASONING_MEDIUM = "/medium",
    REASONING_HIGH   = "/high",
    REASONING_NONE   = "/none",
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
    -- The original implementation removed only a single occurrence of a command
    -- (start, end, or middle) which caused failures when the same slash command
    -- appeared multiple times in the prompt. To support duplicate commands we
    -- repeatedly apply the removal patterns until the prompt stabilises.
    local final_prompt = prompt
    while true do
        local start_of_iteration_prompt = final_prompt
        -- Remove command at the start (optional leading whitespace, mandatory
        -- trailing whitespace to separate from following text).
        final_prompt = final_prompt:gsub("^%s*" .. command .. "%s+", "")
        -- Remove command at the end (preceded by whitespace, optional trailing
        -- whitespace before end of string).
        final_prompt = final_prompt:gsub("%s+" .. command .. "%s*$", "")
        -- Remove command surrounded by whitespace on both sides, preserving a
        -- single space where the command was.
        final_prompt = final_prompt:gsub("(%s+)" .. command .. "%s+", "%1")
        if final_prompt == start_of_iteration_prompt then
            break
        end
    end
    local any_removed = final_prompt ~= prompt
    if any_removed then
        log:info("original prompt: `" .. prompt .. "`")
        log:info("         detect: `" .. command .. "`")
        log:info("     new prompt: `" .. final_prompt .. "`")
    end
    return any_removed, final_prompt
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
        found, rendered_prompt = strip_slash_command_from_prompt(rendered_prompt, cmd)
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

        -- reasoning levels
        [M.slash_commands.REASONING_LOW] = "reasoning_low",
        [M.slash_commands.REASONING_MEDIUM] = "reasoning_medium",
        [M.slash_commands.REASONING_HIGH] = "reasoning_high",
        [M.slash_commands.REASONING_NONE] = "reasoning_none",
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
    log:info("includes", vim.inspect(includes))
    return includes
end

---@param includes ParseIncludesResult
---@return "low"|"medium"|"high"|nil
function M.get_reasoning_level(includes)
    if includes.reasoning_low then
        return "low"
    elseif includes.reasoning_medium then
        return "medium"
    elseif includes.reasoning_high then
        return "high"
    else
        return nil
    end
end

return M
