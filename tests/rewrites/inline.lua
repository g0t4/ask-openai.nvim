local rewrites = require("ask-openai.rewrites.inline")
local assert = require("luassert")



describe("test model responses", function()
    it("should give correct results for simple prompt", function()
        local code = "def add(x, y):"
        local filename = "add.py"
        local user_prompt = "Finish this function"
        local response = rewrites.send_to_ollama(user_prompt, code, filename)

        -- printit
        print(response)

        -- run the response with python and assert result is correct for 2 + 3
        -- cc
        assert.is_equal("def add(x, y):\n  return x + y", response)
    end)
end)
