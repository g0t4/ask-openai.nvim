require("ask-openai.helpers.test_setup").modify_package_path()
local rewrites_frontend = require("ask-openai.rewrites.frontend")
-- FYI be careful how you import init.lua... must be same if imported in multiple spots (i.e. the tests)
local thinking = require("ask-openai.rewrites.thinking")
local assert = require("luassert")

describe("test strip markdown from completion responses", function()
    local function test_strip_md_from_completion(input_text, expected_text)
        -- PRN how about create a class that can handle lines <=> text conversions on-demand so I don't have to think about it?
        local input_lines = vim.split(input_text, "\n")
        local output_lines = rewrites_frontend.strip_md_from_completion(input_lines)
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
