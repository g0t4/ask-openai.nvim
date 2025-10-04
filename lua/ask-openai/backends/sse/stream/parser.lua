-- stream parser will sit BELOW a chat completions client
-- this will buffer data fields in multiline scenarios
-- will split on and emit events when the blank line is detected
-- will have a clean interface for consumers to subscribe to events/done/etc
-- this will plug into my curl_streaming module (and other chat completion endpoint clients)

-- * TERMS:
--   https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#event_stream_format
--   message = series of lines in response w/ one or more fields
--      delimited by blank line ==> \n\n
--   fields = one per line
--     data = payload
--       multiple data lines are concatenated TODO
--     event = type (NOT used in chat completion backends)
--       browser dispatch:
--         addEventListener() for named (typed) events TODO
--         onmessage() when no type TODO

local SSEMessage = {}
SSEMessage.__index = SSEMessage
function SSEMessage:new()
    local instance = setmetatable({}, { __index = SSEMessage })
    return instance
end

---@class SSEStreamParser
---@field _buffer string
---@field _done boolean
---PRN list of events? cache them
---@field _lines {} -- store all received lines here
local SSEStreamParser = {}

function SSEStreamParser:new()
    local instance = setmetatable({}, { __index = self })
    instance._buffer = ""
    instance._done = false
    instance._lines = {}
    return instance
end

--- curl stdout should be patched into this
---@param data string
function SSEStreamParser:write(data)
    table.insert(self._lines, data)
end

function SSEStreamParser:save_to_file()
    -- TODO save to disk in a cache directory so I can replay, analyze event streams per request
    -- TODO save _lines to disk (preserve correct \n breaks)
    --   IOTW join lines with ""
    -- TODO save matching file w/ original request?
end

return SSEStreamParser
