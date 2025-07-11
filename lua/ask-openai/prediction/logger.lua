local ansi = require("ask-openai.prediction.ansi")
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

function clear_iterm_scrollback(file)
    -- * YES iTerm2 scrollback clear:
    --  AND cat works on the file still, it just beeps and shows in every spot it was used (if [a]ppending to file):
    --   38;2;229;192;123m1337;ClearScrollback
    --   which means I can still cat to analyze older logs if needed (rare) while still getting a focused log!
    --   FYI 50 works instead of 1337 too, in my testing
    local clear_iterm_scrolback = "\x1b]1337;ClearScrollback\a"
    file:write(clear_iterm_scrolback)
    file:flush()

    -- * ctrl+L through log
    -- but leaves scrollback (obviously)
    -- local clear_for_tailers = "\27[2J\27[H"
    -- self.file:write(clear_for_tailers)
    -- self.file:flush()
end

function Logger:ensure_file_is_open()
    if not self.file then
        -- data => ~/.local/share/nvim usually
        local path = vim.fn.stdpath("data") .. "/" .. "ask-openai/" .. self.filename
        ensure_directory_exists(path)
        self.file = io.open(path, "a")
        if not self.file then
            error("Failed to open log file: " .. path)
        end

        clear_iterm_scrollback(self.file)

        -- FYI this is only called on FIRST LOG... not on reboot unless reboot has a log call
        --  so it will reset after the first log is written which is fine, just keep in mind
        local header = "\n\n\n============================= NEW NVIM INSTANCE ===========================================\n\n\n"
        self.file:write(header)
    end
end

local LEVEL = {
    TRACE = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3,
}

local function log_level_string(level)
    -- TODO extract out color helpers (i.e. copy over devtools ansi.lua module)
    local lookup = {
        [LEVEL.TRACE] = ansi.cyan("TRACE"),
        [LEVEL.INFO] = ansi.white_bold("INFO "),
        [LEVEL.WARN] = ansi.yellow_bold("WARN "),
        [LEVEL.ERROR] = ansi.red_bold("ERROR"),
    }

    return lookup[level]
end


local function build_entry(level, ...)
    -- CAREFUL with how you use arg table, it's fine to do but it messes up sequential tables (arg is a table)...
    --   #arg => stops at first nil
    --   use select("#", ...) as it doesn't suffer from this issue'
    --   also, can do:    for k,v in ipairs(arg)
    -- FYI using `arg` resulted in parameters from previous calls (w/ more params) to be logged in subsequent logs... IIAC b/c arg was a global somehow?
    local args_strings = {} -- new set of args to write into, don't try to use special `arg` variable
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        -- make sure everything is a string so it can be concatenated
        args_strings[i] = tostring(value)
    end

    return string.format(
        "[%s] %s\n",
        log_level_string(level),
        table.concat(args_strings, " ")
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

function Logger:jsonify_info(message, ...)
    local args = { ... }
    local json = vim.json.encode(args)
    self:json_info(message, json)
end

function Logger:json_info_deferred(message, data)
    vim.defer_fn(function()
        -- TODO handling for when data is not valid json?
        self:json_info(message, data)
    end, 0)
end

function Logger:json_info(message, json, pretty)
    -- TODO add other formats using bat or w/e else
    if json == nil then
        self:info(message, "nil (passed to json_info)")
        return
    end

    -- local command = { "bat", "--style=plain", "--color", "always", "-l", "json" }
    local command = { "jq", ".", "--color-output" }
    pretty = pretty or false
    if not pretty then
        table.insert(command, "--compact-output")
    end

    local job_id = vim.fn.jobstart(command, {
        stdout_buffered = true,
        on_stderr = function(_, data)
            if not data then
                return
            end
            for _, line in ipairs(data) do
                if line:match("^%s*$") then
                    -- skip empty lines
                    return
                end
                -- PRN remove message on every line and just add to first?
                --   FYI most json logging is compact right now so NBD, yet
                self:trace(message, line)
            end
        end,
        on_stdout = function(_, data)
            if not data then
                return
            end
            for _, line in ipairs(data) do
                if line:match("^%s*$") then
                    -- skip empty lines
                    return
                end
                self:trace(message, line)
            end
        end,
        on_exit = function()
        end
    })
    vim.fn.chansend(job_id, json .. "\n")
    vim.fn.chanclose(job_id, "stdin")
end

local verbose = require("ask-openai.config").get_options().verbose

function Logger.is_verbose_enabled()
    return verbose or false
end

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

-- verbose, for troubleshooting
-- intended so I don't replicate this code every time I have a uv.spwan on_exit handler
function Logger:trace_on_exit_always(code, signal)
    -- do not modify this for selective logging
    self:trace("on_exit code:" .. (code or "nil") .. ", signal:" .. (signal or "nil"))
end

-- trace on errors and unexpected conditions only, use this when not troubleshooting
-- intended so I don't replicate this code every time I have a uv.spwan on_exit handler
function Logger:trace_on_exit_errors(code, signal)
    -- FYI on_exit wasn't called when I used handle:kill("sigterm")

    if code ~= nil and code == 0 then
        -- code == 0, signal == 0 => normal exit
        if signal ~= nil and signal ~= 0 then
            -- for now lets see if this ever happens and if I notice it and need to address it
            self:trace("on_exit: unexpected code is 0, signal is non-zero: '" .. signal .. "'")
        end
        return
    end
    -- for now defer all non-zero exit codes to use verbose trace:
    self:trace_on_exit_always(code, signal)
end

-- verbose, for troubleshooting
-- intended so I don't replicate this code every time I have a uv.spwan on_stdout/on_stderr handler
function Logger:trace_stdio_read_always(label, read_error, data)
    -- do not modify this for selective logging
    -- FYI read_error is only for the read operation on the pipe, not the underlying process itself
    if read_error ~= nil then
        -- do not bother with err if its nil, don't need to mention that
        -- ?? dump colorful stack trace
        self:trace(label .. " read_error:", read_error)
    end
    if data == "" then data = "<empty>" end
    self:trace(label .. " data:", data)
    -- ftr... nil prints as "nil"
end

-- less verbose, use this when not troubleshooting
function Logger:trace_stdio_read_errors(label, read_error, _data)
    -- FYI read_error is only for the read operation on the pipe, not the underlying process itself
    if read_error ~= nil then
        -- ?? dump colorful stack trace
        self:trace(label .. " read_error:", read_error)
    end
end

-- *** NOOP LOGGER STUBS TO SHUT DOWN 99% of expense of logging
NOOP_LOGGER = {}
NOOP_LOGGER = setmetatable({}, { __index = Logger })
function NOOP_LOGGER:log(...)
end

function NOOP_LOGGER:json_info(...)
end

local DISABLED = false
-- local DISABLED = true
local predictions_logger = nil
function Logger.predictions()
    if DISABLED then
        return NOOP_LOGGER
    end

    if predictions_logger then
        return predictions_logger
    end
    predictions_logger = Logger:new("ask-predictions.log")
    return predictions_logger
end

return Logger
