local log = require("ask-openai.logs.logger").predictions()
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
M.slash_commands = { "/yanks", "/all", "/commits", "/file", "/files", "/tools", "/selection", "/template", "/norag", }

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
        all = (prompt == "") or has("/all"),
        yanks = has("/yanks"),
        commits = has("/commits"),
        current_file = has("/file"),
        open_files = has("/files"),
        use_tools = has("/tools"),
        apply_template_only = has("/template"), -- TODO for AskRewrite/AskQuestion (popup window with colorful prompt?)
        include_selection = has("/selection"),
        top_k = top_k,
        cleaned_prompt = prompt,
        norag = has("/norag"),
    }

    if includes.all then
        includes.yanks = true
        includes.commits = true
        includes.current_file = true
        includes.open_files = true
        -- ? do I want all to include tools/selection too? for now leave them off (all doesn't have to mean every slash command)
    end

    for _, k in ipairs(M.slash_commands) do
        includes.cleaned_prompt = clean_prompt(includes.cleaned_prompt, k)
    end

    log:info("includes", vim.inspect(includes))
    return includes
end

return M
