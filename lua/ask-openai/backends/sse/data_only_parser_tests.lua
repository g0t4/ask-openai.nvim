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

                it("should track in _lines", function()
                    assert.same({ write1 }, parser._lines)
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

            it("only one newline at end => treats as SSE", function()
                local write1 = llama_server_error_no_end_newlines .. "\n"
                parser:write(write1)
                assert.are.same({ llama_server_error_no_end_newlines }, events)
            end)

            it("NO newline at end => treats as SSE", function()
                local write1 = llama_server_error_no_end_newlines
                parser:write(write1)
                assert.are.same({ llama_server_error_no_end_newlines }, events)
            end)
        end)

        describe("dregs is not valid JSON object", function()
            local not_valid_json = "notvalidjson"

            it("only one newline at end => logs warning", function()
                local write1 = not_valid_json .. "\n"
                parser:write(write1)
                assert.are.same({}, events)
                -- TODO validate warning
            end)

            it("NO newline at end => logs warning", function()
                local write1 = not_valid_json
                parser:write(write1)
                assert.are.same({}, events)
                -- TODO validate warning
            end)
        end)
    end)

    -- PRN strip comments test case -- if I have a server that does this?
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
