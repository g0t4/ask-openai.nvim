local log = require("ask-openai.prediction.logger").predictions()

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

return M
