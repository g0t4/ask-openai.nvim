local SSEStreamParser = require("ask-openai.backends.sse.stream.parser")

describe("data-only events", function()
    local events = {}
    local function data_only_handler(data)
        table.insert(events, data)
    end
    local parser
    before_each(function()
        events = {}
        parser = SSEStreamParser.new(data_only_handler)
    end)

    it("single data line", function()
        local write1 = "data: event1\n\n"

        parser:write(write1)
        assert.same({ write1 }, parser._lines)
        assert.are.same({ "event1" }, events)
    end)

    it("multiple data lines", function()
        local write1 = "data: event1\n"
        local write2 = "data: event2\n\n"

        parser:write(write1)
        parser:write(write2)
        assert.same({ write1, write2 }, parser._lines)
        -- assert.are.same({ "event1" }, events)
    end)

    it("single data line, split across multiple writes", function()
        local write1 = "data: even"
        local write2 = "t1\n\n"

        parser:write(write1)
        parser:write(write2)
        assert.same({ write1, write2 }, parser._lines)
        assert.are.same({ "event1" }, events)
    end)

    describe("no trailing \n\n emits no events", function()
        it("only \n at end", function()

        end)
    end)

    -- TODO strip comments test case

    -- TODO! curl-stream-sses-weather.out

    -- TODO! make sure to devise a test of this:
    --   lua/ask-openai/tools/tests/captures/multi-line-sse.json
    --   or ensure it is covered in the above sceanrios


    -- data: YHOO
    -- data: +2
    -- data: 10
end)
