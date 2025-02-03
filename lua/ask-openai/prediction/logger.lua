local Logger = {}
Logger.__index = Logger

local module_loaded_at = vim.loop.hrtime()

local predictions_logger = nil
function Logger.predictions()
    if predictions_logger then
        return predictions_logger
    end
    predictions_logger = Logger:new("ask-predictions.log")
    return predictions_logger
end

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
        self.file = io.open(path, "w")
        if not self.file then
            error("Failed to open log file: " .. path)
        end
    end
end

local LEVEL = {
    TRACE = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3,
}

local function log_level_string(level)
    local lookup = {
        [LEVEL.TRACE] = "TRACE",
        [LEVEL.INFO] = "INFO",
        [LEVEL.WARN] = "WARN",
        [LEVEL.ERROR] = "ERROR",
    }
    return lookup[level]
end

local function build_entry(level, ...)
    -- CAREFUL with how you use arg table, it's fine to do but it messes up sequential tables (arg is a table)...
    --   #arg => stops at first nil
    --   use select("#", ...) as it doesn't suffer from this issue'
    --   also, can do:    for k,v in ipairs(arg)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        -- make sure everything is a string so it can be concatenated
        arg[i] = tostring(value)
    end
    local elapsed = (vim.loop.hrtime() - module_loaded_at) / 1e9 -- added for us/ns level timing of messages since os.time/date() doesn't go beyond sec (IIRC)


    return string.format(
        "[%.3f]sec [%s] %s\n",
        elapsed,
        log_level_string(level),
        table.concat(arg, " ")
    )
end

function Logger:error(...)
    self:log(LEVEL.ERROR, ...)
end

function Logger:warn(...)
    self:log(LEVEL.WARN, ...)
end

function Logger:trace(...)
    self:log(LEVEL.TRACE, ...)
end

-- TODO add unit test of info log method so I don't waste another hour on its quirks:
-- log:info("foo", nil, "bar") -- use to validate nil args don't interupt the rest of log args getting included -- nuke this is fine, just leaving as a reminder I had trouble with logging nil values

function Logger:info(...)
    self:log(LEVEL.INFO, ...)
end

local verbose = require("ask-openai.config").get_options().verbose

function Logger:log(level, ...)
    if not verbose and level < 2 then
        return
    end

    -- TODO adapt to have a level? and add filter for it
    local entry = build_entry(level, ...)

    -- PRN can use vim.defer_fn if overhead is interferring with predictions... don't  care to do that now though...
    self:ensure_file_is_open() -- ~11ms first time only (when ask dir already exists, so worse case is higher if it has to make the dir), 0 thereafter
    self.file:write(entry) -- 0.01ms => 0.00ms
    self.file:flush() -- 0.69ms (max in my tests) => down to 0.02ms (most of time)
end

return Logger
