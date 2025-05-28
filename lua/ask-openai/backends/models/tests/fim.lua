local fim = require("ask-openai.backends.models.fim")

local test_setup = require("ask-openai.helpers.test_setup")
test_setup.modify_package_path()
local should = require("devtools.tests.should")

describe("qwen2.5-coder", function()
    -- *** File-level FIM template:
    --   <|fim_prefix|>{code_pre}<|fim_suffix|>{code_suf}<|fim_middle|>{code_mid}<|endoftext|>
    --   from Tech Report: https://arxiv.org/pdf/2409.12187
    --   official example: https://github.com/QwenLM/Qwen2.5-Coder/blob/main/examples/Qwen2.5-Coder-fim.py

    it("get_fim_prompt", function()
        -- USE example:
        --   https://github.com/QwenLM/Qwen2.5-Coder/blob/main/examples/Qwen2.5-Coder-repolevel-fim.py

        local request = {
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
        local prompt = fim.qwen25coder.get_fim_prompt(request)

        -- TODO confirm \n after each file contents? or not?
        --    is it required? otherwise if optional, then it doesn't matter
        local expected = "<|repo_name|>my_repo_name\n" -- TODO confirm if \n after repo name
            .. "<|file_sep|>nvim-recent-yanks.txt\nyanks"
            -- .. "<|file_sep|>path/to/current.lua\n"
            -- .. "<|fim_prefix|>foo\nthe\nprefix"
            -- .. "<|fim_suffix|>bar\nbaz"
            -- .. "<|fim_middle|>"

        should.be_equal(expected, prompt)
    end)
end)

describe("starcoder2", function()
    -- by the way, the following would be used if I didn't have "raw" on the request (that's PSM right there!)
    --    ollama show --template starcoder2:7b-q8_0
    --
    -- <file_sep>
    -- {{- if .Suffix }}<fim_prefix>
    -- {{ .Prompt }}<fim_suffix>{{ .Suffix }}<fim_middle>
    -- {{- else }}{{ .Prompt }}
    -- {{- end }}<|end_of_text|>
    --
    --  BUT... <|end_of_text|> is not the right tag?! its' <|endoftext|>
    --   i.e. https://github.com/bigcode-project/starcoder2/issues/10#issuecomment-1979014959

    it("get_fim_prompt", function()
        local request = {
            -- TODO add type def for this request/backend/builder type
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

describe("mellum", function()
    -- TODO! WOA! mellum docs show an SPM FIM!!! (not PSM)
    -- I will assume it was trained on both... b/c its working right now with PSM

    -- * docs commit history => all SPM
    --
    -- - https://huggingface.co/JetBrains/Mellum-4b-base/commit/b7d42cacc4ea2889f32479777266fb731248a3d8
    --     * oldest => initial add of example
    --     encoded_input = tokenizer(f"<fim_suffix>suffix<fim_prefix>{prefix}<fim_middle>", return_tensors='pt', return_token_type_ids=False)
    --
    -- - https://huggingface.co/JetBrains/Mellum-4b-base/commit/4179e39f97ed12c1de07de86f3e194e36badec23
    --     * just fixed {} around suffix
    --     FYI seems to be an alterante format for no repo_name/filepaths
    --     encoded_input = tokenizer(f"<fim_suffix>{suffix}<fim_prefix>{prefix}<fim_middle>", return_tensors='pt', return_token_type_ids=False)
    --
    -- - https://huggingface.co/JetBrains/Mellum-4b-base/commit/ddf77ce4289722d1bfd59a34b8899500c2ce87c8
    --     * introduced the repo level FIM template
    --     example = """<filename>utils.py
    --     def multiply(x, y):
    --         return x * y
    --     <filename>config.py
    --     DEBUG = True
    --     MAX_VALUE = 100
    --     <filename>example.py
    --     <fim_suffix>
    --
    --     # Test the function
    --     result = calculate_sum(5, 10)
    --     print(result)<fim_prefix>def calculate_sum(a, b):
    --     <fim_middle>"""
    --
    --     encoded_input = tokenizer(example, return_tensors='pt', return_token_type_ids=False)
    --

    it("get_fim_prompt", function()
        local request = {
            -- TODO add type def for this request/backend/builder type
            prefix = "foo\nthe\nprefix",
            suffix = "bar\nbaz",
            current_context = {
                yanks = "yanks",
            },
            get_current_file_path = function()
                return "path/to/current.lua"
            end,
            get_repo_name = function()
                return "my_mellum_repo"
            end
        }
        local prompt = fim.mellum.get_fim_prompt(request)

        -- TODO is repo_name ok here? or was it not trained with?
        --  only spot I've seen mention: https://huggingface.co/JetBrains/Mellum-4b-base/blob/main/special_tokens_map.json
        local expected = "<reponame>my_mellum_repo<filename>nvim-recent-yanks.txt\nyanks"
            -- NOTE the filename comes before the fim_suffix tag (unlike StarCoder2 where filename comes after fim_prefix tag)
            .. "<filename>path/to/current.lua\n"
            .. "<fim_suffix>bar\nbaz"
            .. "<fim_prefix>foo\nthe\nprefix"
            .. "<fim_middle>"
        should.be_equal(expected, prompt)
    end)

    -- btw
    -- no hints in prompt template:
    --   ollama show --template huggingface.co/JetBrains/Mellum-4b-base-gguf:latest
    -- {{ .Prompt }}
    --
    --  TLDR => raw!
end)
