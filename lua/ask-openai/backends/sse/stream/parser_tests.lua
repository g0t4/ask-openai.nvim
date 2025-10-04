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

    describe("single data line", function()
        local write1 = "data: event1\n\n"

        before_each(function()
            parser:write(write1)
        end)

        it("should emit event", function()
            assert.are.same({ "event1" }, events)
        end)

        it("should track in _lines", function()
            assert.same({ write1 }, parser._lines)
        end)
    end)

    it("concatenate multiple data with new line at end of first, is preserved", function()
        -- no different than if the \n were in the middle of the data value
        local write1 = "data: hello\n"
        local write2 = "data: world\n\n"

        parser:write(write1)
        parser:write(write2)
        assert.are.same({ "hello\nworld" }, events)
    end)

    it("concatenate multiple data lines in same event", function()
        local write1 = "data: hello"
        local write2 = "data: world\n\n"

        parser:write(write1)
        parser:write(write2)
        assert.are.same({ "helloworld" }, events)
    end)

    it("single data line, split across multiple writes", function()
        local write1 = "data: even"
        local write2 = "t1\n\n"

        parser:write(write1)
        parser:write(write2)
        assert.are.same({ "event1" }, events)
    end)

    it("multiple \n\n in single write", function()
        -- TODO
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
