local Logger = {}
Logger.__index = Logger

function Logger:new(filename)
    local self = setmetatable({}, Logger)
    self.filename = filename
    self.file = nil
    return self
end

local function ensure_directory_exists(path)
    local dir = path:match("^(.+)/[^/]+$")
    if dir and not os.execute("mkdir -p " .. dir) then
        error("Failed to create directory: " .. dir)
    end
end

function Logger:ensure_file_is_open()
    if not self.file then
        -- data => ~/.local/share/nvim usually
        local path = vim.fn.stdpath("data") .. "/" .. "ask/" .. self.filename
        ensure_directory_exists(path)
        self.file = io.open(path, "a")
        if not self.file then
            error("Failed to open log file: " .. path)
        end
    end
end

function Logger:log(...)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local entry = string.format("[%s] %s\n", timestamp, ...)

    -- PRN can use vim.defer_fn if overhead is interferring with predictions... don't  care to do that now though...
    self:ensure_file_is_open()
    self.file:write(entry)
    self.file:flush()
end

return Logger
