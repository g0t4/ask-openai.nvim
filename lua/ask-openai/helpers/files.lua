local log = require("ask-openai.logs.logger").predictions()
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
function M.read_file_string(file_path)
    if vim.fn.filereadable(file_path) == 0 then
        log:info("read_file_string failed to read: " .. tostring(file_path) .. " does not exist!")
        return nil
    end
    local file = io.open(file_path, "r")
    local content = file:read("*a")
    file:close()
    return content
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

return M
