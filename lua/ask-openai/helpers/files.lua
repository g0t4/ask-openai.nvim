local log = require("ask-openai.logs.logger").predictions()

local M = {}

---@param file_path string
---@return string[]
function M.read_file_lines(file_path)
    if vim.fn.filereadable(file_path) == 0 then
        log:info("read_file_lines failed to read: " .. tostring(file_path) .. " does not exist!")
        return {}
    end
    local lines = {}
    for line in io.lines(file_path) do
        table.insert(lines, line)
    end
    return lines
end

---@param file_path string
---@return string?
function M.read_text(file_path)
    file_path = vim.fn.expand(file_path)
    if vim.fn.filereadable(file_path) == 0 then
        log:info("read_text failed to read: " .. tostring(file_path) .. " does not exist!")
        return nil
    end
    local file = io.open(file_path, "r")
    local content = file:read("*a")
    file:close()
    return content
end

function M.get_file_absolute_path(bufnr)
    bufnr = bufnr or 0
    return vim.api.nvim_buf_get_name(bufnr)
end

function M.get_file_relative_path(bufnr)
    bufnr = bufnr or 0
    local absolute_path = vim.api.nvim_buf_get_name(bufnr)
    local relative_path = vim.fn.fnamemodify(absolute_path, ":.")
    return relative_path
end

function M.get_current_file_relative_path()
    -- returns full path to files outside of PWD
    return vim.fn.expand("%")
end

function M.get_current_file_absolute_path()
    return vim.fn.expand("%:p")
end

function M.exists(path)
    local stat = vim.uv.fs_stat(path)
    return stat ~= nil
end

function M.list_directories(path)
    local entries = M.list_entries(path)

    local dirs = vim.iter(entries)
        :filter(function(entry) return entry.type == "directory" end)
        :map(function(entry) return entry.name end)
        :totable()

    return dirs
end

function M.list_entries(path)
    if not vim.fn.isdirectory(path) then
        return {}
    end

    local dir = vim.uv.fs_opendir(path, nil, 100)
    if dir == nil then
        return {}
    end

    local entries = {}
    local has_more = true

    while has_more do
        -- fs_readdir returns # entries (at a time) specified in fs_opendir
        local batch_of_entries = vim.uv.fs_readdir(dir)
        -- log:info("batch", vim.inspect(batch_of_entries))
        if not batch_of_entries then
            break
        end

        for _, entry in ipairs(batch_of_entries) do
            table.insert(entries, entry)
        end

        has_more = #batch_of_entries > 0
    end

    return entries
end

--- Get the CWD's repo root directory.
--- - failures are logged already
--- - consumers only need to check for repo_root == nil
---@return string|nil repo_root -- nil = cannot find repo_root, or this is not a git repo
function M.get_repo_root()
    local rev_parse = vim.fn.systemlist('git rev-parse --show-toplevel')
    if vim.v.shell_error ~= 0 then
        log:info("git rev-parse --show-toplevel failed with error", vim.inspect(vim.v.shell_error))
        return nil
    end
    if #rev_parse == 0 then
        log:info("git rev-parse returned empty output")
        return nil
    end
    local repo_root = vim.fn.trim(rev_parse[1])
    if not vim.fn.isdirectory(repo_root) then
        log:error("git rev-parse returned path that is not a directory:", vim.inspect(repo_root))
        return nil
    end
    return repo_root, nil
end

return M
