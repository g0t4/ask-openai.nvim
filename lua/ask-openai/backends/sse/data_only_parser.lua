local log = require("ask-openai.logs.logger").predictions()

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

---@alias SSEOnDataHandler function(data string)

---Think of this as unwrapping the SSE envelope, extracting events and triggering handlers
---for each event type, though in this case data is the only event needed (thus far)
---
---This should work for more than just OpenAI endpoints... any data only SSE endpoint
---
---@class SSEDataOnlyParser
---@field _buffer string
---@field _done boolean
---@field _lines {} -- store all received lines here
---@field _on_data_sse SSEOnDataHandler
local SSEDataOnlyParser = {}

--- @param on_data_sse SSEOnDataHandler
--- @return SSEDataOnlyParser
function SSEDataOnlyParser.new(on_data_sse)
    local instance = setmetatable({}, { __index = SSEDataOnlyParser })
    instance._buffer = ""
    instance._done = false
    instance._lines = {}
    instance._on_data_sse = on_data_sse
    return instance
end

---@return string? invalid_dreg -- if the buffer has leftover, invalid JSON, return an error describing it
function SSEDataOnlyParser:flush_dregs()
    local no_dregs = not self._buffer or self._buffer == ""
    if no_dregs then
        return nil
    end

    local success, sse_parsed = pcall(vim.json.decode, self._buffer)
    if not success then
        -- TODO? just flush it to _on_data_sse every time and let that blow up (it has error handler in it)?
        --   if I want terminate behavior then this would be wise
        return "invalid json: " .. self._buffer
    end
    self._on_data_sse(self._buffer)
end

--- curl stdout should be patched into this
---@param data string
function SSEDataOnlyParser:write(data)
    table.insert(self._lines, data)
    -- log:info("data", vim.inspect(data))
    -- log:info("_lines", vim.inspect(self._lines))

    -- FYI assumed to be all data events so this is fine, to strip before inserting in buffer
    data = data:gsub("^data: ", "")
    data = data:gsub("\r\n", "\n"):gsub("\r", "\n") -- normalize line endings to LF

    self._buffer = self._buffer .. data
    local lines = vim.split(self._buffer, "\n\n", {})
    -- FYI split takes plain and trimempty option values
    --   default not removing empties, can use to check if a \n\n was present
    if (#lines == 1) then
        log:error("POSSIBLE DREG")
        -- no \n\n
        return -- buffer is fine as-is
    elseif (#lines >= 2) then
        -- had \n\n ==> emit all but last one

        for i = 1, #lines - 1 do
            local event = lines[i]

            event = event:gsub("^data: ", "") -- happens when multiple in one message
            -- FTR I am not a fan of this, feels sloppy but thank god I split out this low-level event parser... nightmare to do this in same loop that uses deltas!

            self._on_data_sse(event)
        end

        -- keep last one in buffer for next
        self._buffer = lines[#lines]
        log:error("POSSIBLE DREG")
    end
end

return SSEDataOnlyParser
