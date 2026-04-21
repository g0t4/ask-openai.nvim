local log = require("ask-openai.logs.logger").predictions()
local safely = require("ask-openai.helpers.safely")

-- stream parser will sit BELOW a chat completions client
-- this will buffer data fields in multiline scenarios
-- will split on and emit events when the blank line is detected
-- will have a clean interface for consumers to subscribe to events/done/etc
-- this will plug into my curl module (and other chat completion endpoint clients)

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

---@alias SSEOnDataHandler function(data string)

---Think of this as unwrapping the SSE envelope, extracting events and triggering handlers
---for each event type, though in this case data is the only event needed (thus far)
---
---This should work for more than just OpenAI endpoints... any data only SSE endpoint
---
---@class SSEDataOnlyParser
---@field _buffer string
---@field _done boolean
---@field _on_data_sse SSEOnDataHandler
local SSEDataOnlyParser = {}

---@param on_data_sse SSEOnDataHandler
---@return SSEDataOnlyParser
function SSEDataOnlyParser.new(on_data_sse)
    local instance = setmetatable({}, { __index = SSEDataOnlyParser })
    instance._buffer = ""
    instance._done = false
    instance._on_data_sse = on_data_sse
    return instance
end

---@return string? invalid_dreg -- if the buffer has leftover, invalid JSON, return an error describing it
function SSEDataOnlyParser:flush_dregs()
    local no_dregs = not self._buffer or self._buffer == ""
    if no_dregs then
        return nil
    end

    local success, sse_parsed = safely.decode_json(self._buffer)
    if not success then
        return "invalid json in dregs: " .. self._buffer
    end

    -- PRN? just flush it to _on_data_sse every time and let that blow up
    -- (it has error handler in it)
    --   if I want terminate behavior then this would be wise

    -- YES I know this means the parsed JSON object is discarded and re-parsed in:
    self._on_data_sse(self._buffer)
end

--- curl stdout should be patched into this
---@param data string
function SSEDataOnlyParser:write(data)
    -- log:info("data", vim.inspect(data))

    -- normalize line endings to LF
    data = data:gsub("\r\n", "\n"):gsub("\r", "\n")

    -- FYI assumed data only => strip data: prefix
    -- data = data:gsub("^data: ", "")

    self._buffer = self._buffer .. data

    -- * look for blank line (signals end of data event)
    -- FYI split takes plain and trimempty options
    --   default not removing empties, can use to check if a \n\n was present
    local events = vim.split(self._buffer, "\n\n", {})

    if (#events == 1) then
        -- no blank line (yet)
        return
    elseif (#events >= 2) then
        -- had blank line(s)

        -- ==> emit completed data event(s)
        for i = 1, #events - 1 do
            local event = events[i]
            -- SSEs (events) are comprised of \n delimited fields
            local fields = vim.split(event, "\n")
            -- strip data: prefix on each field (assume all are data)
            local data = vim.iter(fields)
                :map(function(f)
                    -- TODO later can handle or parse or otherwise split the field name and value (i.e. for event: message)
                    local result, _ = f:gsub("^data: ", "")
                    return result
                end)
                :join("\n")
            self._on_data_sse(data)
        end

        -- keep last line in buffer (it's not complete w/o a blank line)
        self._buffer = events[#events]
    end
end

--- Write multiple chunks sequentially.
--- currently for testing
---@param writes string[] List of data chunks to write.
function SSEDataOnlyParser:writes(writes)
    for _, chunk in ipairs(writes) do
        self:write(chunk)
    end
end

return SSEDataOnlyParser
