local rewrites = require("lua.ask-openai.rewrites.inline")
local assert = require("luassert")

-- TODO anything else to port for "inline2" => I already did the text=>lines fix
--   I cannot recall what inline2 was about... but seems lines might have been part of it

describe("test strip markdown from completion responses", function()
    it("should remove markdown from a simple completion", function()
        local completion = "```\nfoo\n```"
        local lines = vim.split(completion, "\n")
        local response = rewrites.strip_md_from_completion(lines)
        assert.are.same({"foo"}, response)
    end)
    it("should remove markdown block with filetype specified", function()
        local completion = "```python\nfoo\n```"
        local lines = vim.split(completion, "\n")
        local response = rewrites.strip_md_from_completion(lines)
        assert.are.same({"foo"}, response)
    end)
    it("should not remove code blocks in the middle of the completion", function()
        -- i.e. when completing markdown content, maybe I should have a special check for that? cuz then wouldn't it be reasonable to even allow a full completion that is one code block?
        local completion = "This is some text\n```\nprint('Hello World')\n```\nfoo the bar"
        local lines = vim.split(completion, "\n")
        local response = rewrites.strip_md_from_completion(lines)
        assert.are.same(response, lines)
    end)
    it("should remove special html tags <foo> and </foo>", function()
        local completion = "This is some text with <foo>special tag</foo> and more text."
        local lines = vim.split(completion, "\n")
        local response = rewrites.strip_md_from_completion(lines)
        assert.are.same({"This is some text with  and more text."}, response)
    end)
    it("should remove multiple special html tags", function()
        local completion = "Multiple <foo>tags</foo> and <bar>another</bar> and <baz>one more</baz>."
        local lines = vim.split(completion, "\n")
        local response = rewrites.strip_md_from_completion(lines)
        assert.are.same({"Multiple  and  and ."}, response)
    end)
    it("should not remove other html tags", function()
        local completion = "This is a <div>normal html tag</div> and <p>some text</p>."
        local lines = vim.split(completion, "\n")
        local response = rewrites.strip_md_from_completion(lines)
        assert.are.same({"This is a <div>normal html tag</div> and <p>some text</p>."}, response)
    end)
    -- PRN can I find a library/algo someone already setup to do this?
    -- or can I use structured outputs with ollama? I know I can with vllm... that might help too
end)


