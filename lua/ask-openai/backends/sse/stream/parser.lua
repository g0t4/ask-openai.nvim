-- stream parser will sit BELOW a chat completions client
-- this will buffer data fields in multiline scenarios
-- will split on and emit events when the blank line is detected
-- will have a clean interface for consumers to subscribe to events/done/etc
-- this will plug into my curl_streaming module (and other chat completion endpoint clients)

-- * FORMAT:
-- https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#event_stream_format
-- ^: == comment (often used as keep-alive)
-- UTF-8
-- mimetype: https://html.spec.whatwg.org/multipage/iana.html#text/event-stream
-- SPEC:
--   https://html.spec.whatwg.org/multipage/server-sent-events.html#parsing-an-event-stream
--
-- event (aka message)
--   separated by a pair of newline characters
--   delimited by blank line ==> \n\n
--   have field(s)
-- data field
--   multiple data lines are concatenated
--   thus far I have only observed data-only events (IOTW no other fields)
--
-- browser event dispatch:
--   addEventListener() for named (typed) events
--   onmessage() when no type

---@alias SSEDataOnlyHandler function(data string)

---@class SSEStreamParser
---@field _buffer string
---@field _done boolean
---@field _lines {} -- store all received lines here
---@field _data_only_handler SSEDataOnlyHandler
local SSEStreamParser = {}

--- @param data_only_handler SSEDataOnlyHandler
--- @return SSEStreamParser
function SSEStreamParser.new(data_only_handler)
    local instance = setmetatable({}, { __index = SSEStreamParser })
    instance._buffer = ""
    instance._done = false
    instance._lines = {}
    instance._data_only_handler = data_only_handler
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
    --   probably should move this logic out and let consumer get _lines and do all of this
end

return SSEStreamParser
