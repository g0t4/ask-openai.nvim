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
end

function M.starcoder2.get_fim_prompt(request)
    -- FYI! see notes in starcoder2.md

    -- <repo_name>reponame<file_sep>filepath0\ncode0<file_sep><fim_prefix>filepath1\ncode1_pre<fim_suffix>code1_suf<fim_middle>code1_mid<file_sep> ...<|endoftext|>
    -- TODO <|endoftext|> to stop tokens? must already be set IIGC cuz I get completions that terminate appropriately, quite often
    local tokens = M.starcoder2.sentinel_tokens

    -- TODO confirm repo naming? is it just basename of repo root? or GH link? or org/repo?
    local repo_name = vim.fn.getcwd():match("([^/]+)$")
    local prompt = tokens.repo_name .. repo_name


    -- * recent yanks
    if request.current_context.yanks ~= "" then
        local filepath = "nvim-recent-yanks.txt"
        -- FYI now its clear the extra \n\n is part of the file contents... so if that isn't needed in the file I should remove one or both!
        local file_contents = request.current_context.yanks .. "\n\n"
        local context_file_prompt = tokens.file_sep .. filepath .. "\n"
            .. file_contents
        prompt = prompt .. context_file_prompt
    end

    -- * recent edits
    -- local recent_changes = "Here are some recent lines that were edited by the user: "
    -- for _, change in pairs(current_context.edits) do
    --     local str = string.format("Line %d, Column %d: %s", change.lnum, change.col, change.line)
    --     -- todo include line/col or not?
    --     -- todo include file?
    --     recent_changes = recent_changes .. "\n" .. str
    -- end
    -- raw_prompt = recent_changes .. "\n\n" .. raw_prompt

    -- * FIM file
    log:trace("prefix", "'" .. request.prefix .. "'")
    log:trace("suffix", "'" .. request.suffix .. "'")
    --
    -- TODO ESCAPE presence of any sentinel tokens! i.e. should be rare but if someone is working on LLM code it may not be!
    --
    local file_level_fim_prompt = tokens.fim_prefix
        .. request.prefix
        .. tokens.fim_suffix
        .. request.suffix
        .. tokens.fim_middle


    -- PRN is this a better way to get filename?
    -- local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(CURRENT_BUFFER), ":t")
    local current_file_path = vim.fn.expand('%'):match("([^/]+)$")

    if current_file_path == nil then
        -- i.e. if :new and before first :w (save)
        -- for now just leave filename blank?
        --  or, maybe mark it as new?
        --   can I deterine filetype using some heuristic or other metadata?
        --   should I mark it "new"
        log:warn("current_file_name is nil")
        current_file_path = ""
    end

    -- confirmed: starcoder2 adds \n after filepath
    local fim_file = tokens.file_sep .. current_file_path .. "\n"
        .. file_level_fim_prompt
    -- WARNING: anything after <|fim_middle|> is seen as part of the completion!
    prompt = prompt .. fim_file

    return prompt
end

return M
