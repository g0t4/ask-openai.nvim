local rewrites = require("ask-openai.rewrites.inline")
local assert = require("luassert")

describe("test strip markdown from completion responses", function()
    it("should remove markdown from a simple completion", function()
        local completion = "```\nfoo\n```"
        local response = rewrites.strip_md_from_completion(completion)
        assert.are.equal("foo", response)
    end)
    it("should remove markdown block with filetype specified", function()
        local completion = "```python\nfoo\n```"
        local response = rewrites.strip_md_from_completion(completion)
        assert.are.equal("foo", response)
    end)
    it("should not remove code blocks in the middle of the completion", function()
        -- i.e. when completing markdown content, maybe I should have a special check for that? cuz then wouldn't it be reasonable to even allow a full completion that is one code block?
        local completion = "This is some text\n```\nprint('Hello World')\n```\nfoo the bar"
        local response = rewrites.strip_md_from_completion(completion)
        assert.are.equal(response, completion)
    end)
    -- PRN can I find a library/algo someone already setup to do this?
    -- or can I use structured outputs with ollama? I know I can with vllm... that might help too
end)
