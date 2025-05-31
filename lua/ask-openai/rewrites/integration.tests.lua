local rewrites = require("ask-openai.rewrites.inline")
local assert = require("luassert")

-- TODO PORT TO WORK WITH inline2

-- TODO find a test framework that doesn't have a dependency on my entire F'ing neovim config OR fix the paths for the tests to run
--   right now it breaks on my werkspace plugin needing nvim-tree ... which I don't give a F about in these tests

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

    it("should leave existing comments in tact", function()
        -- TODO can I get it to repro removing a comment in an example? or did it remove it for another reason?
        -- FYI I asked it to not add comments, which led it to remove comments in existing code which I don't wanna do :) either
        local code = "print(1+1)\n# This is a comment\ndef add(x, y):"
        local filename = "add.py"
        local user_prompt = "Finish this function"
        local response = rewrites.send_to_ollama(user_prompt, code, filename)

        print(response)

        local hasComment = string.match(response, '# This is a comment')
        assert.is_not_nil(hasComment, 'response does not have original comment')
    end)

end)
