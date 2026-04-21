require("ask-openai.helpers.test_setup").modify_package_path()
local SSEDataOnlyParser = require("ask-openai.backends.sse.data_only_parser")
local describe = require("devtools.tests._describe")

describe("data-only events", function()
    local events = {}
    local function on_data_sse(data)
        table.insert(events, data)
    end
    local parser
    before_each(function()
        events = {}
        parser = SSEDataOnlyParser.new(on_data_sse)
    end)

    local function escape_newlines(s)
        -- this is for display purposes in test description headers
        return s:gsub("\n", "\\n"):gsub("\r", "\\r")
    end

    local line_ending_types = { "\n", "\r\n", "\r" }
    for _, line_ending in ipairs(line_ending_types) do
        local blank_line = line_ending .. line_ending
        describe(escape_newlines(blank_line), function()
            -- FYI I am ONLY testing this one case with \r and \r\n endings... I don't really think I will ever encounter this
            --  and I don't want to muck up my LF ending tests that make sense to me and should be all I ever see on *nix anyways
            --  FTR it would be fine to strip out the \r and \r\n handling entirely

            describe("single data value in single write", function()
                local write1 = 'data: data_value1' .. blank_line
                before_each(function()
                    parser:write(write1)
                end)

                it("should emit event", function()
                    assert.are.same({ "data_value1" }, events)
                end)
            end)
        end)
    end

    it("concatenate split write data value with newline at end of first write, preserves value's newline", function()
        -- FYI it is possible this is not how I should combine when there are multiple data labels, in that case I might need to concat with \n in between
        --   for now I am leaving this as is as I have yet to see it in the wild with openai compatible streaming endpoints, so I can't easily verify one way or the other
        --   in this case if I concat w/ \n then I should have "hello\n\nworld"

        -- no different than if the \n were in the middle of the data value
        local write1 = "data: hello\n"
        local write2 = "data: world\n\n"

        parser:write(write1)
        parser:write(write2)
        assert.are.same({ "hello\nworld" }, events)
    end)

    it("concatenate split write data value (single event)", function()
        -- FYI it is possible this is not how I should combine when there are multiple data labels, in that case I might need to concat with \n in between
        --   for now I am leaving this as is as I have yet to see it in the wild with openai compatible streaming endpoints, so I can't easily verify one way or the other
        --   in this case if I concat w/ \n then I should have "hello\nworld"

        local write1 = "data: hello"
        local write2 = "data: world\n\n"

        parser:write(write1)
        parser:write(write2)
        assert.are.same({ "helloworld" }, events)
    end)

    it("concatenate split write data value without 'data: ' prefix on second write", function()
        -- FYI AFAICT this is NOT PER the spec... and is just my intution looking at how llama-server generates this one large final SSE (w/ verbose logging turned on)
        -- see multi-line-sse.json which makes it pretty clear no \n is intended between the two lines
        -- so even if I change 2+ data lables to use \n I would likely leave this as is with no \n added in middle

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
        -- FYI this might be a problem with concat multiple data labels, see notes above in other similar tests... for now this is FINE as is until I get a real world test case to invalidate it
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

    describe("dregs with no trailing blank line", function()
        describe("dregs is valid JSON", function()
            -- (via llama server error object when no --jinja flag and try to use tools)
            local llama_server_error_no_end_newlines = [[{"error":{"code":500,"message":"tools param requires --jinja flag","type":"server_error"}}]]
            -- ALSO no `data: ` prefix - DO NOT test that here too (split it apart if you want that test case to use this scenario too)

            -- PRN! add flush_dregs to an integration test?
            --   manual testing: remove --jinja, try using tools!

            it("only one newline at end => treats as SSE", function()
                local write1 = llama_server_error_no_end_newlines .. "\n"
                parser:write(write1)

                local error_text = parser:flush_dregs() -- intended to be called in on_exit assert.are.same({ write1 }, events)

                assert.are.same({ write1 }, events)
                assert.are.same(nil, error_text)
            end)

            it("NO newline at end => treats as SSE", function()
                local write1 = llama_server_error_no_end_newlines
                parser:write(write1)

                local error_text = parser:flush_dregs()

                assert.are.same({ write1 }, events)
                assert.are.same(nil, error_text)
            end)
        end)

        describe("dregs is not valid JSON object", function()
            local not_valid_json = "notvalidjson"

            it("only one newline at end => logs warning", function()
                local write1 = not_valid_json .. "\n"
                parser:write(write1)

                local error_text = parser:flush_dregs()

                assert.are.same({}, events)
                assert.are.same("invalid json in dregs: notvalidjson\n", error_text)
            end)

            it("NO newline at end => logs warning", function()
                local write1 = not_valid_json
                parser:write(write1)

                local error_text = parser:flush_dregs()

                assert.are.same({}, events)
                assert.are.same("invalid json in dregs: notvalidjson", error_text)
            end)
        end)
    end)

    -- TODO do I support concatenating multiple `data:` lines? (with only \n delimiter, not \n\n which is the event delimiter)
    --   read more here: https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#data

    describe("ignore event field in Named events, IOTW treat like data-only message", function()
        -- "Named event" == event+data field per message
        --   read more: https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#named_events

        -- FYI wait for a need to parse more or all fields before adding that
        -- - PRN id field
        -- - PRN retry field
        -- - PRN ignore invalid field names
        --
        -- FYI just ignore event field for now to support MCP HTTP streamable transport

        describe("single write", function()
            it("single SSE", function()
                local write = "event: message\n" .. "data: {\"test\": 1}\n\n"
                parser:write(write)
                assert.are.same({ '{"test": 1}' }, events)
            end)

            it("multiple SSEs", function()
                local write = "event: message\n" .. "data: {\"a\":1}\n\n" ..
                    "event: message\n" .. "data: {\"b\":2}\n\n"
                parser:write(write)
                assert.are.same({ '{"a":1}', '{"b":2}' }, events)
            end)
        end)

        describe("split write", function()
            describe("single SSE", function()
                it("each field on its own line", function()
                    parser:writes {
                        'event: message\n',
                        'data: {"d":4}\n\n',
                    }
                    assert.are.same({ '{"d":4}' }, events)
                end)
                describe("split within event field's line", function()
                    it("even[SPLIT]t: message", function()
                        parser:writes {
                            'even',
                            't: message\ndata: {"c":3}\n\n',
                        }
                        assert.are.same({ '{"c":3}' }, events)
                    end)
                    it("event:[SPLIT] message", function()
                        parser:writes {
                            'event:',
                            ' message\ndata: {"c":3}\n\n',
                        }
                        assert.are.same({ '{"c":3}' }, events)
                    end)
                    it("event: mes[SPLIT]sage", function()
                        parser:writes {
                            'event:',
                            ' message\ndata: {"c":3}\n\n',
                        }
                        assert.are.same({ '{"c":3}' }, events)
                    end)
                    it("triple split event field's line", function()
                        parser:writes {
                            "even",
                            "t: mess",
                            'age\ndata: {"f":6}\n\n',
                        }
                        assert.are.same({ '{"f":6}' }, events)
                    end)
                end)
            end)
            describe("multiple SSEs", function()
                it("every line split in middle somewhere", function()
                    parser:writes {
                        "ev",
                        "ent: message\n",
                        "da",
                        "ta: {\"a\":1}\n\n",
                        "ev",
                        "ent: message\n",
                        "da",
                        "ta: {\"b\":2}\n\n",
                    }
                    assert.are.same({ '{"a":1}', '{"b":2}' }, events)
                end)
            end)
        end)

        it("multiple data events across separate writes", function()
            local write1 = "event: message\ndata: {\"x\":10}\n\n"
            local write2 = "event: message\ndata: {\"y\":20}\n\n"
            parser:write(write1)
            parser:write(write2)
            assert.are.same({ '{"x":10}', '{"y":20}' }, events)
        end)

        it("repeated split write of data events", function()
            local write1 = "event: message\n"
            local write2 = "data: {\"x\":10}\n\n"
            local write3 = "event: message\n"
            local write4 = "data: {\"y\":20}\n\n"
            parser:write(write1)
            parser:write(write2)
            parser:write(write3)
            parser:write(write4)
            assert.are.same({ '{"x":10}', '{"y":20}' }, events)
        end)
    end)

    -- TODO comments:
    -- describe("ignore comments", function()
    --     it("single data event with a comment before", function()
    --         local write = ": this is a comment\n" .. "data: {\"test\": 1}\n\n"
    --         parser:write(write)
    --         assert.are.same({ '{"test": 1}' }, events)
    --     end)
    -- end)
end)

describe("integration test - completion captures", function()
    -- TODO! curl-stream-sses-weather.out


    it("mult-line-sse.json", function()
        local contents = vim.fn.readfile("lua/ask-openai/tools/tests/captures/multi-line-sse.json")
        -- lines are split => but those split are not actual \n in the original curl stdout output

        local events = {}
        local parser = SSEDataOnlyParser.new(function(data)
            table.insert(events, data)
        end)
        vim.iter(contents):each(function(line)
            --  by convention empty line == \n
            --  I added one extra empty line before and after "done"
            --  others already had two between each
            --  TODO find out if any odd behavior with actual \n ... especially around "done"
            if (line == "") then
                -- empty line == \n
                parser:write("\n")
            else
                parser:write(line)
            end
        end)

        assert.equal(5, #events)
        -- FYI I counted 16634 by hand:
        --  though I do wonder if the 5 spaces at start of second line should only be 4?
        --  if no label is there still a space at start of the line?
        assert.equal(16634, #(events[4]))
    end)


    -- data: YHOO
    -- data: +2
    -- data: 10
end)
