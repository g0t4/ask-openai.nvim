local log = require("ask-openai.logs.logger").predictions()
local files = require("ask-openai.helpers.files")

-- global instructs: `~/.agents/instructs`
-- per repo: `.agents/instructs`

local M = {}

-- Cache of instruct name -> absolute path of the instruct markdown file
M._instruct_paths_by_name = {}
-- Cache of instruct name -> instruct md contents
M._instruct_contents_by_name = {}

---@param raw string
---@return string cleaned
function M.clean_contents(raw)
    local content = raw

    -- Remove YAML front‑matter
    if content:match("^%-%-%-") then
        -- Remove everything from the opening '---' to the next closing '---' line,
        -- and consume any following whitespace (including CRLF line endings).
        content = content:gsub("^%-%-%-.-%-%-%-%s*", "")
    end

    -- strip HTML comments (non‑greedy)
    content = content:gsub("<!--.-?-->", "")

    content = vim.trim(content)
    return content
end

--- The content is cached after the first read.
---@param name string The name of the instruct
---@return string|nil The instruct contents after stripping HTML comments and YAML front‑matter,
---                or nil if the instruct cannot be found.
function M.load_instruct(name)
    if not name or name == "" then
        error("instruct name is required for load_instruct")
    end

    if M._instruct_contents_by_name[name] then
        return M._instruct_contents_by_name[name]
    end

    if not M._instruct_paths_by_name[name] then
        -- Populate paths (TODO I don't like this.. rename get_instruct_slash_commands or split out some functionality)
        M.get_instruct_slash_commands()
    end

    local path = M._instruct_paths_by_name[name]
    if not path or vim.fn.filereadable(path) == 0 then
        log:error(string.format("instruct file not found: %s", name))
        return nil
    end

    local raw = files.read_text(path)
    if not raw then
        log:error(string.format("Empty instruct %s in %s", name, path))
        return nil
    end

    local content = M.clean_contents(raw)
    M._instruct_contents_by_name[name] = content
    return content
end

M.cached_instruct_slash_commands = nil
--- List of slash commands for instructs (cached after first load)
---@return string[] List of slash commands (e.g., "/my_instruct")
function M.get_instruct_slash_commands()
    if M.cached_instruct_slash_commands then
        return M.cached_instruct_slash_commands
    end

    local instructs_path = vim.fn.expand("~/.agents/instructs")
    local names = {}
    if vim.fn.isdirectory(instructs_path) == 1 then
        -- * load instruct directories
        local dir_names = files.list_directories(instructs_path)
        for _, name in ipairs(dir_names) do
            M._instruct_paths_by_name[name] = instructs_path .. "/" .. name .. "/INSTRUCT.md"
            table.insert(names, name)
        end

        -- * plus standalone markdown files
        local entries = files.list_entries(instructs_path)
        for _, entry in ipairs(entries) do
            if entry.type == "file" and entry.name:match("%.md$") then
                local instruct_name = entry.name:gsub("%.md$", "")
                -- FYI this means directory wins over standalone markdown file
                if M._instruct_paths_by_name[instruct_name] then
                    vim.notify(string.format(
                        "Instruct name collision: '%s' already registered from directory %s; ignoring standalone %s",
                        instruct_name,
                        M._instruct_paths_by_name[instruct_name],
                        instructs_path .. "/" .. entry.name
                    ), vim.log.levels.WARN)
                else
                    M._instruct_paths_by_name[instruct_name] = instructs_path .. "/" .. entry.name
                    table.insert(names, instruct_name)
                end
            end
        end
    end
    M.cached_instruct_slash_commands = names
    return names
end

return M
