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

    describe("single data value in single write", function()
        local write1 = 'data: data_value1\n\n'

        before_each(function()
            parser:write(write1)
        end)

        it("should emit event", function()
            assert.are.same({ "data_value1" }, events)
        end)

        it("should track in _lines", function()
            assert.same({ write1 }, parser._lines)
        end)
    end)

    it("concatenate split write data value with newline at end of first write, preserves value's newline", function()
        -- no different than if the \n were in the middle of the data value
        local write1 = "data: hello\n"
        local write2 = "data: world\n\n"

        parser:write(write1)
        parser:write(write2)
        assert.are.same({ "hello\nworld" }, events)
    end)

    it("concatenate split write data value (single event)", function()
        local write1 = "data: hello"
        local write2 = "data: world\n\n"

        parser:write(write1)
        parser:write(write2)
        assert.are.same({ "helloworld" }, events)
    end)

    it("concatenate split write data value without 'data: ' prefix on second write", function()
        local write1 = "data: data_va"
        local write2 = "lue1\n\n"

        parser:write(write1)
        parser:write(write2)
        assert.are.same({ "data_value1" }, events)
    end)

    it("multiple events in single write", function()
        local write = "data: hello\n\ndata: world\n\n"

        parser:write(write)
        assert.are.same({ "hello", "world" }, events)
    end)

    it("'data: ' at start of a multi write, single event's data value", function()
        -- edge case - make sure the second 'data: ' is preserved
        local write1 = 'data: {"code": "local my_var = \\"my_'
        local write2 = 'data: data: bar\\""}\n\n'

        parser:write(write1)
        parser:write(write2)

        assert.are.same({ '{"code": "local my_var = \\"my_data: bar\\""}' }, events)
    end)

    -- it("'data: ' is at the start of a new event's data value", function()
    --     -- FYI this won't ever happen w/ json payload
    --     --   SO, DO NOT TEST THIS
    --     local write = "data: data: \n\n"
    --     parser:write(write)
    --     assert.are.same({ "data: " }, events)
    -- end)

    describe("no trailing blank line emits no events", function()
        it("only on newline at end", function()
            -- FYI this test exists mostly so I am documenting my thought process
            --  b/c no doubt I will wonder what about new line at end in the future!
            --  this helps make my intent explicit!

            local write1 = "data: data_value1\n"
            parser:write(write1)
            assert.are.same({}, events)
            -- TODO? emit some sort of warning on a done message?
            --   so I can log a warning?
        end)

        it("no new lines at end", function()
            local write1 = "data: data_value1"
            parser:write(write1)
            assert.are.same({}, events)
        end)
    end)

    -- TODO strip comments test case


    -- TODO! it is imperative to add test cases with json payloads
    --    AND/OR to convert the above into json examples

    -- TODO! curl-stream-sses-weather.out

    -- TODO! make sure to devise a test of this:
    --   lua/ask-openai/tools/tests/captures/multi-line-sse.json
    --   or ensure it is covered in the above sceanrios


    -- data: YHOO
    -- data: +2
    -- data: 10
end)
