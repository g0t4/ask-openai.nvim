local rewrites = require("lua.ask-openai.rewrites.inline")
local assert = require("luassert")
-- TODO PORT TO WORK WITH inline2

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
    -- PRN can I find a library/algo someone already setup to do this?
    -- or can I use structured outputs with ollama? I know I can with vllm... that might help too
end)
