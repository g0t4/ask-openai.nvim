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


        local expected = "<repo_name>ask-openai.nvim<file_sep>nvim-recent-yanks.txt\nyanks"
            -- TODO fix passing current file name
            .. "<file_sep><fim_prefix>\n"
            -- .. "<file_sep><fim_prefix>lua/ask-openai/backends/models/tests/fim.lua\n"
            .. "foo\nthe\nprefix"
            .. "<fim_suffix>bar\nbaz"
            .. "<fim_middle>"

        should.be_equal(expected, prompt)
    end)
end)
