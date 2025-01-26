local Logger = {}
Logger.__index = Logger

-- purposes:
-- - only open file once per process
-- - only check for directory existence once
-- - reduce overhead for callers (after first hit)
-- - PRN further reduce overhead for callers (i.e. queue writing / schedule later)
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
    self:ensure_file_is_open() -- ~11ms first time only (when ask dir already exists, so worse case is higher if it has to make the dir), 0 thereafter
    self.file:write(entry)     -- 0.01ms => 0.00ms
    self.file:flush()          -- 0.69ms (max in my tests) => down to 0.02ms (most of time)
end

return Logger
