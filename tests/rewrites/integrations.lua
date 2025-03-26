local rewrites = require("ask-openai.rewrites.inline")
local assert = require("luassert")

describe("test model responses", function()
    it("should give correct results for simple prompt", function()
        local code = "def add(x, y):"
        local filename = "add.py"
        local user_prompt = "Finish this function"
        local response = rewrites.send_to_ollama(user_prompt, code, filename)

        print(response)

        -- just use assert to compare and if match then no need to look further
        --   else, can visually compare
        --   mostly looking for no ``` and ` in response
        assert.is_nil(string.match(response, '```'), 'response has ```')
        assert.is_nil(string.match(response, '`'), 'response has backtick')

        assert.is_equal("def add(x, y):\n    return x + y", response)
    end)
end)

