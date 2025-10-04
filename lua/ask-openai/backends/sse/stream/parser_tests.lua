local SSEStreamParser = require("ask-openai.backends.sse.stream.parser")


-- REFER TO PARSING "SPEC":
-- https://html.spec.whatwg.org/multipage/server-sent-events.html#parsing-an-event-stream
--
-- mimetype:
--   https://html.spec.whatwg.org/multipage/iana.html#text/event-stream
--
-- format:
--   https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#event_stream_format
--   UTF-8
--   * messages are separated by a pair of newline characters
--   ^: == comment (often used as keep-alive)

describe("data-only events", function()
    it("single data line", function()
        local parser = SSEStreamParser:new()
        local write1 = "data: event1\n\n"
        local events = {}
        -- parser:_listen("data", function(event)
        --     table.insert(events, event)
        -- end)
        parser:write(write1)
        assert.same({ write1 }, parser._lines)
        -- assert.are.same({ "event1" }, events)
    end)

    it("multiple data lines", function()
        local parser = SSEStreamParser:new()
        local write1 = "data: event1\n"
        local write2 = "data: event2\n\n"
        local events = {}
        -- parser:_listen("data", function(event)
        --     table.insert(events, event)
        -- end)
        parser:write(write1)
        parser:write(write2)
        assert.same({ write1, write2 }, parser._lines)
        -- assert.are.same({ "event1" }, events)
    end)

    it("single data line, split across multiple writes", function()
        local parser = SSEStreamParser:new()
        local write1 = "data: even"
        local write2 = "t1\n\n"
        local events = {}
        -- parser:_listen("data", function(event)
        --     table.insert(events, event)
        -- end)
        parser:write(write1)
        parser:write(write2)
        assert.same({ write1, write2 }, parser._lines)
        -- assert.are.same({ "event1" }, events)
    end)

    describe("no trailing \n\n emits no events", function()
        it("only \n at end", function()

        end)
    end)

    -- TODO strip comments

    -- TODO! make sure to devise a test of this:
    --   lua/ask-openai/tools/tests/captures/multi-line-sse.json
    --   or ensure it is covered in the above sceanrios


    -- data: YHOO
    -- data: +2
    -- data: 10
end)
