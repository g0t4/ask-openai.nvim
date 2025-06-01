require("ask-openai.helpers.test_setup").modify_package_path()
local rewrites = require("ask-openai.rewrites.inline")
-- FYI be careful how you import init.lua... must be same if imported in multiple spots (i.e. the tests)
local thinking = require("ask-openai.rewrites.thinking")
local assert = require("luassert")

describe("test strip markdown from completion responses", function()
    local function test_strip_md_from_completion(input_text, expected_text)
        -- PRN how about create a class that can handle lines <=> text conversions on-demand so I don't have to think about it?
        local input_lines = vim.split(input_text, "\n")
        local output_lines = rewrites.strip_md_from_completion(input_lines)
        local output_text = table.concat(output_lines, "\n")
        assert.are.same(expected_text, output_text)
    end

    it("should remove markdown from a simple completion", function()
        local input_text = "```\nfoo\n```"
        local expected_text = "foo"
        test_strip_md_from_completion(input_text, expected_text)
    end)

    it("should remove markdown block with filetype specified", function()
        local input_text = "```python\nfoo\n```"
        local expected_text = "foo"
        test_strip_md_from_completion(input_text, expected_text)
    end)

    it("should not remove code blocks in the middle of the completion", function()
        -- i.e. when completing markdown content, maybe I should have a special check for that? cuz then wouldn't it be reasonable to even allow a full completion that is one code block?
        local input_text = "This is some text\n```\nprint('Hello World')\n```\nfoo the bar"
        test_strip_md_from_completion(input_text, input_text)
    end)
    -- PRN can I find a library/algo someone already setup to do this?
    -- or can I use structured outputs with ollama? I know I can with vllm... that might help too
end)

describe("test strip html thinking tags from full completion responses", function()
    -- BTW... don't include the think tag example if you want help...
    -- it ends up stopping the model when it first reflects on the closing tag

    -- TODO add a test case to comment out and keep the think tags...
    --   pass comment char(s) as arg, with text, and tag_name
    --   have it find the thinking section, "take it out"
    --   "split them on new lines"
    --   prefix each line w/ comment char
    --   that way, if there was any code (shouldn't be but just in case) on the close tag line after close tag... it gets pushed down a line and not commented out

    local function test_strip_thinking_tags(input_text, expected_text)
        local input_lines = vim.split(input_text, "\n")
        thinking.set_thinking_tag_and_patterns("foo") -- just to avoid the special tag in code I might want to dog food help with
        local output_lines = thinking.strip_thinking_tags(input_lines)
        local output_text = table.concat(output_lines, "\n")
        assert.are.same(expected_text, output_text)
    end

    it("should remove one set of thinking html tags <foo> and </foo> when they come first", function()
        local input_text = "<foo>special tag</foo> and more text."
        local expected_text = " and more text."
        test_strip_thinking_tags(input_text, expected_text)
    end)

    -- TODO greedy testing:
    -- { "</foo>", "<foo>special </foo> tag</foo> and more text.", " tag</foo> and more text." }

    it("if there are two closing tags, it should stop right after the first one", function()
        local input_text = "<foo>special tag</foo> and more text.</foo> foo"
        local expected_text = " and more text.</foo> foo"
        test_strip_thinking_tags(input_text, expected_text)
    end)

    describe("handling partial/full unrelated tags inside thinking tags", function()
        -- TODO what is the specified behavior, should this ever happen?
        local partial_cases = {
            { "< (less than sign)",      "<foo>special < tag</foo> and more text.",     " and more text." },
            { "> (greater than sign)",   "<foo>special > tag</foo> and more text.",     " and more text." },
            { "</ (partial close tag)",  "<foo>special </ tag</foo> and more text.",    " and more text." },
            { "<foo> (extra start tag)", "<foo>special <foo> tag</foo> and more text.", " and more text." },
        }

        for _, case in ipairs(partial_cases) do
            local case_description = case[1]
            local input_text = case[2]
            local expected_text = case[3]
            it("should ignore " .. case_description .. "< inside think tags", function()
                test_strip_thinking_tags(input_text, expected_text)
            end)
        end
    end)

    it("should NOT remove one set of thinking html tags \n<foo> and </foo> when they don't come first, even if starts at start of a line", function()
        local input_text = "This is some text with <foo>special tag</foo> and more text."
        test_strip_thinking_tags(input_text, input_text)
    end)

    it("should NOT remove one set of thinking html tags <foo> and </foo> when they don't come first", function()
        local input_text = "This is some text with <foo>special tag</foo> and more text."
        test_strip_thinking_tags(input_text, input_text)
    end)

    it("when multiple tagged regions, should only remove the first one", function()
        local input_text = "<foo>tags</foo> and <foo>another</foo> and <foo>one more</foo>."
        local expected_text = " and <foo>another</foo> and <foo>one more</foo>."
        test_strip_thinking_tags(input_text, expected_text)
    end)

    it("should not remove other html tags", function()
        local input_text = "This is a <div>normal html tag</div> and <p>some text</p>."
        local expected_text = "This is a <div>normal html tag</div> and <p>some text</p>."
        test_strip_thinking_tags(input_text, expected_text)
    end)

    it("when only open tag, should do nothing", function()
        -- FYI I might want another streaming helper that can strip it out after open tag detected... that can be separate or incorporated later
        local input_text = "<foo>special tag foo the bar."
        local input_lines = vim.split(input_text, "\n")
        thinking.set_thinking_tag_and_patterns("foo")
        local output_lines, open_without_close_yet = thinking.strip_thinking_tags(input_lines)
        local output_text = table.concat(output_lines, "\n")
        assert.are.same(input_text, output_text)
        assert.are.equal(thinking.ThinkingStatus.Thinking, open_without_close_yet)
    end)

    it("when only closing tag, should do nothing", function()
        local input_text = "foo the </foo> bar."
        local expected_text = input_text
        test_strip_thinking_tags(input_text, expected_text)
    end)
end)
