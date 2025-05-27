local fim = require("ask-openai.backends.models.fim")

local test_setup = require("ask-openai.helpers.test_setup")
test_setup.modify_package_path()
local should = require("devtools.tests.should")


describe("starcoder2", function()
    it("get_fim_prompt", function()
        local request = {
            prefix = "foo\nthe\nprefix",
            suffix = "bar\nbaz",
            current_context = {
                yanks = "yanks",
            },
        }
        local prompt = fim.starcoder2.get_fim_prompt(request)
        local expected = ""
        should.be_equal(expected, prompt)
    end)
end)
