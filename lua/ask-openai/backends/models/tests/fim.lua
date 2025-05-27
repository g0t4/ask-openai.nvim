local fim = require("ask-openai.backends.models.fim")

local test_setup = require("ask-openai.helpers.test_setup")
test_setup.modify_package_path()
local should = require("devtools.tests.should")


describe("starcoder2", function()
    it("get_fim_prompt", function()
        local request = {
            -- TODO! add type def for this request/backend/builder type
            prefix = "foo\nthe\nprefix",
            suffix = "bar\nbaz",
            current_context = {
                yanks = "yanks",
            },
            get_current_file_path = function()
                return "path/to/current.lua"
            end,
            get_repo_name = function()
                return "my_repo_name"
            end
        }
        local prompt = fim.starcoder2.get_fim_prompt(request)

        local expected = "<repo_name>my_repo_name<file_sep>nvim-recent-yanks.txt\nyanks"
            .. "<file_sep><fim_prefix>path/to/current.lua\n"
            .. "foo\nthe\nprefix"
            .. "<fim_suffix>bar\nbaz"
            .. "<fim_middle>"

        should.be_equal(expected, prompt)
    end)

    -- TODO need to do some integration testing of a better way to generate git commit messages
    --   starcoder2 (at least) and IIRC qwen... refuse to pull symbols from suffix only...
    --   nevermind it cleary a commit message!!!
    --     file even called .git/COMMIT_EDITMSG
    --   maybe put all of it as a separate context file?
    --   or have special reminder prompt in this case
end)
