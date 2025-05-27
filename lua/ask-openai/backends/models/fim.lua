local log = require("ask-openai.prediction.logger").predictions()

local M = {}

-- these models work for other purposes too...
--   but lets collect them under fim for now
--   really these are the fim related special tokens

M.qwen25coder = {
    sentinel_tokens = {
        -- https://huggingface.co/Qwen/Qwen2.5-Coder-14B-Instruct/blob/main/tokenizer_config.json
        fim_prefix = "<|fim_prefix|>",
        fim_middle = "<|fim_middle|>",
        fim_suffix = "<|fim_suffix|>",
        -- fim_pad = "<|fim_pad|>",
        repo_name = "<|repo_name|>",
        file_sep = "<|file_sep|>",

        im_start = "<|im_start|>",
        im_end = "<|im_end|>",
        -- endoftext = "<|endoftext|>"
    },
}

M.mellum = {
    -- https://huggingface.co/JetBrains/Mellum-4b-base/blob/main/special_tokens_map.json
    -- much in common with starcoder2
    sentinel_tokens = {

        -- FIM
        fim_prefix = "<fim_prefix>",
        fim_middle = "<fim_middle>",
        fim_suffix = "<fim_suffix>",
        fim_pad = "<fim_pad>",
        -- FYI file_sep => filename, repo_name => reponame... can put that back if the prompt is unique to mellum anyways
        --  but right now I suspect it will be the same as qwen25coder and starcoder2
        file_sep = "<filename>",
        repo_name = "<reponame>",

        -- roles:
        system = "<system>",
        slash_system = "</system>",
        assistant = "<assistant>",
        slash_assistant = "</assistant>",
        user = "<user>",
        slash_user = "</user>",

        think = "<think>",
        slash_think = "</think>",

        gh_stars = "<gh_stars>",

        -- PRN was base trained on commit messages? or were these just reserved for future use?
        commit_after = "<commit_after>",
        commit_before = "<commit_before>",
        commit_msg = "<commit_msg>",

        issue_start = "<issue_start>",
        issue_comment = "<issue_comment>",
        issue_closed = "<issue_closed>",

        jupyter_start = "<jupyter_start>",
        jupyter_code = "<jupyter_code>",
        jupyter_text = "<jupyter_text>",
        jupyter_output = "<jupyter_output>",
        empty_output = "<empty_output>",

        bos_token = "<|endoftext|>",
        eos_token = "<|endoftext|>",
        pad_token = "<|endoftext|>",
        unk_token = "<|endoftext|>",

    },
}

M.starcoder2 = {
    -- PRN did starcoder v1 have diff special tokens?
    sentinel_tokens = {
        -- https://huggingface.co/bigcode/starcoder2-15b/blob/main/special_tokens_map.json
        fim_prefix = "<fim_prefix>",
        fim_middle = "<fim_middle>",
        fim_suffix = "<fim_suffix>",
        fim_pad = "<fim_pad>",
        file_sep = "<file_sep>",
        repo_name = "<repo_name>",

        endoftext = "<|endoftext|>",
        issue_start = "<issue_start>",
        issue_comment = "<issue_comment>",
        issue_closed = "<issue_closed>",
        jupyter_start = "<jupyter_start>",
        jupyter_text = "<jupyter_text>",
        jupyter_code = "<jupyter_code>",
        jupyter_output = "<jupyter_output>",
        jupyter_script = "<jupyter_script>",
        empty_output = "<empty_output>",
        code_to_intermediate = "<code_to_intermediate>",
        intermediate_to_code = "<intermediate_to_code>",


        pr_start = "<pr>",
        pr_status = "<pr_status>",
        pr_is_merged = "<pr_is_merged>",
        pr_base = "<pr_base>",
        pr_file = "<pr_file>",
        pr_base_code = "<pr_base_code>",
        pr_diff = "<pr_diff>",
        pr_diff_hunk = "<pr_diff_hunk>",
        pr_comment = "<pr_comment>",

        pr_event_id = "<pr_event_id>",
        pr_review = "<pr_review>",
        pr_review_state = "<pr_review_state>",
        pr_review_comment = "<pr_review_comment>",
        pr_in_reply_to_review_id = "<pr_in_reply_to_review_id>",
        pr_in_reply_to_comment_id = "<pr_in_reply_to_comment_id>",

        pr_diff_hunk_comment_line = "<pr_diff_hunk_comment_line>",

        -- "<NAME>",
        -- "<EMAIL>",
        -- "<KEY>",
        -- "<PASSWORD>"
    }
}

function M.mellum.get_fim_prompt()
    -- TODO, does it support repo/file or both level context?
    -- TODO!

    -- TODO! WOA! mellum docs show an SPM FIM!!! (not PSM)
    -- was it trained on both or just one?
    --
    -- * docs commit history => all SPM
    --
    -- - https://huggingface.co/JetBrains/Mellum-4b-base/commit/b7d42cacc4ea2889f32479777266fb731248a3d8
    --     * oldest => initial add of example
    --     encoded_input = tokenizer(f"<fim_suffix>suffix<fim_prefix>{prefix}<fim_middle>", return_tensors='pt', return_token_type_ids=False)
    --
    -- - https://huggingface.co/JetBrains/Mellum-4b-base/commit/4179e39f97ed12c1de07de86f3e194e36badec23
    --     * just fixed {} around suffix
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
end

function M.starcoder2.get_spm_fim_prompt(request)
    -- TODO add support for SPM (also)...
    -- investigate perf differences
    -- i.e. kv cache impact
    --
    -- StarCoder2 supports both:
    --   https://github.com/bigcode-project/starcoder2/issues/14   --
    --   was trained on 50/50
    --   IIRC so was Qwen2.5-Coder?
    --     TODO investigate if Qwen2.5-Coder supports SPM
end

function M.starcoder2.get_fim_prompt(request)
    -- FYI! see notes in starcoder2.md

    -- <repo_name>reponame<file_sep>filepath0\ncode0<file_sep><fim_prefix>filepath1\ncode1_pre<fim_suffix>code1_suf<fim_middle>code1_mid<file_sep> ...<|endoftext|>
    -- TODO <|endoftext|> to stop tokens? must already be set IIGC cuz I get completions that terminate appropriately, quite often
    --   TODO add <file_sep> to STOP tokens?
    --      https://github.com/bigcode-project/starcoder2/issues/10#issuecomment-2214157190
    --      is it already setup that way?
    local tokens = M.starcoder2.sentinel_tokens

    -- TODO confirm repo naming? is it just basename of repo root? or GH link? or org/repo?
    local repo_name = request.get_repo_name()
    local prompt = tokens.repo_name .. repo_name

    local function append_file_non_fim(file_path, file_contents)
        -- <file_sep>filepath0\ncode0
        local non_fim_file = tokens.file_sep .. file_path .. "\n" .. file_contents
        prompt = prompt .. non_fim_file
    end

    -- * recent yanks
    if request.current_context.yanks ~= "" then
        local file_path = "nvim-recent-yanks.txt"
        local file_contents = request.current_context.yanks
        append_file_non_fim(file_path, file_contents)
    end

    -- * recent edits
    -- local recent_changes = "Here are some recent lines that were edited by the user: "
    -- for _, change in pairs(current_context.edits) do
    --     local str = string.format("Line %d, Column %d: %s", change.lnum, change.col, change.line)
    --     -- todo include line/col or not?
    --     -- todo include file?
    -- end
    -- TODO append_file_non_fim("nvim-recent-edits.txt", recent_changes)
    --    TODO one edits file? or group changes PER file? or one file per edit?
    --    TODO what is the file_path and file_contents (per file) - make it clear

    -- * FIM file
    log:trace("prefix", "'" .. request.prefix .. "'")
    log:trace("suffix", "'" .. request.suffix .. "'")

    -- TODO add to qwen code too
    -- local current_file_path = vim.fn.expand('%'):match("([^/]+)$")
    local current_file_path = request.get_current_file_path()
    if current_file_path == nil then
        -- i.e. if :new and before first :w (save)
        -- for now just leave filename blank?
        --  or, maybe mark it as new?
        --   can I deterine filetype using some heuristic or other metadata?
        --   should I mark it "new"
        log:warn("current_file_name is nil")
        current_file_path = ""
        -- TODO! what to do here? should I switch the entire prompt away from reponame/filepath (or can I just do one file?)
    end
    --
    -- TODO ESCAPE presence of any sentinel tokens? i.e. should be rare but if someone is working on LLM code it may not be!
    --
    -- FYI carefully observe the format:
    --   <file_sep><fim_prefix>filepath1\ncode1_pre<fim_suffix>code1_suf<fim_middle>code1_mid
    --   <fim_prefix> comes BEFORE filepath!
    local fim_file_contents = tokens.fim_prefix
        .. current_file_path
        .. "\n"
        .. request.prefix
        .. tokens.fim_suffix
        .. request.suffix
        .. tokens.fim_middle

    local fim_file = tokens.file_sep .. fim_file_contents
    prompt = prompt .. fim_file

    -- WARNING: anything after <|fim_middle|> is seen as part of the completion!

    return prompt
end

return M
