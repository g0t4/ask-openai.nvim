local fim = require("ask-openai.backends.models.fim")
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

    end)
end)
