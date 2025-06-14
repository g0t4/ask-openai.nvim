local prompts = require("ask-openai.prediction.context.prompts")
require('ask-openai.helpers.testing')

describe("parse_includes", function()
    describe("/all", function()
        it("' /all ' in middle is stripped, and removes one whitespace char (after)", function()
            local includes = prompts.parse_includes("foo /all bar")
            assert.is_true(includes.all)
            assert.are_equal("foo bar", includes.cleaned_prompt)
        end)
        it("'/all ' at start is stripped with whitespace (after)", function()
            local includes = prompts.parse_includes("/all foo")
            assert.is_true(includes.all)
            assert.are_equal("foo", includes.cleaned_prompt)
        end)
        it("' /all' at end is stripped", function()
            local includes = prompts.parse_includes("foo /all")
            assert.is_true(includes.all)
            assert.are_equal("foo", includes.cleaned_prompt)
        end)
        it("'/allFoo' - in front of word is not stripped", function()
            -- whitespace after, at start
            local at_start = "/allFoo "
            local includes = prompts.parse_includes(at_start)
            assert.is_false(includes.all)
            assert.are_equal(at_start, includes.cleaned_prompt)

            -- whitespace before, at end
            local at_end = " /allFoo"
            local includes = prompts.parse_includes(at_end)
            assert.is_false(includes.all)
            assert.are_equal(at_end, includes.cleaned_prompt)

            -- in middle
            local in_middle = " /allFoo "
            local includes = prompts.parse_includes(in_middle)
            assert.is_false(includes.all)
            assert.are_equal(in_middle, includes.cleaned_prompt)
        end)
        it("'foo/allbar' - in between word is not stripped", function()
            local at_start = "foo/allbar "
            local includes = prompts.parse_includes(at_start)
            assert.is_false(includes.all)
            assert.are_equal(at_start, includes.cleaned_prompt)

            local at_end = " foo/allbar"
            local includes = prompts.parse_includes(at_end)
            assert.is_false(includes.all)
            assert.are_equal(at_end, includes.cleaned_prompt)

            local in_middle = " foo/allbar "
            local includes = prompts.parse_includes(in_middle)
            assert.is_false(includes.all)
            assert.are_equal(in_middle, includes.cleaned_prompt)
        end)
        -- it("'/allbar' - at end of word is not stripped", function()
        --     local includes = prompts.parse_includes("/allbar")
        --     assert.is_false(includes.all)
        --     assert.are_equal("/allbar", includes.cleaned_prompt)
        -- end)
    end)
end)
