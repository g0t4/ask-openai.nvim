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

function M.qwen25coder.get_fim_prompt(request)
    -- FYI! see fim.md for extensive FIM notes
    local tokens = M.qwen25coder.sentinel_tokens

    -- TODO! confirm qwen2.5coder has trailing \n after repo_name
    --   I see this in the example files: https://github.com/QwenLM/Qwen2.5-Coder/blob/f20915b77910de5ba8463547e7654beb056ec7d0/examples/Qwen2.5-Coder-repolevel-fim.py
    --   it might not matter?
    local repo_name = request:get_repo_name()
    local prompt = tokens.repo_name .. repo_name .. "\n"

    local function append_file_non_fim(file_path, file_contents)
        -- <file_sep>filepath0\ncode0
        local non_fim_file = tokens.file_sep .. file_path .. "\n" .. file_contents
        prompt = prompt .. non_fim_file
    end

    -- * ctags
    -- if request.current_context.ctags_files ~= nil then
    --     local files = request.current_context.ctags_files
    --     log:trace("ctags_files sizes: " .. #files[1] .. " " .. #files[2])
    --     -- for _, f in files do
    --     append_file_non_fim("devtools/tags", files[1])
    --     append_file_non_fim("tags", files[2])
    --     -- end
    -- end

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
    --     recent_changes = recent_changes .. "\n" .. str
    -- end
    -- raw_prompt = recent_changes .. "\n\n" .. raw_prompt

    -- * FIM file
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
    local fim_file_contents = tokens.file_sep
        .. current_file_path
        .. "\n"
        .. tokens.fim_prefix
        .. request.prefix
        .. tokens.fim_suffix
        .. request.suffix
        .. tokens.fim_middle

    -- WARNING: anything after <|fim_middle|> is seen as part of the completion!

    return prompt .. fim_file_contents
end

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

function M.mellum.get_fim_prompt(request)
    -- FYI! see test case for mellum, I have a bunch of notes over there
    local tokens = M.mellum.sentinel_tokens

    -- * repo_name
    local repo_name = request.get_repo_name()
    local prompt = tokens.repo_name .. repo_name

    local function append_file_non_fim(file_path, file_contents)
        -- <filename>filepathX\ncodeX
        local non_fim_file = tokens.file_sep .. file_path .. "\n" .. file_contents
        prompt = prompt .. non_fim_file
    end

    -- * recent yanks
    if request.current_context.yanks ~= "" then
        local file_path = "nvim-recent-yanks.txt"
        local file_contents = request.current_context.yanks
        append_file_non_fim(file_path, file_contents)
    end

    -- * TODO recent edits

    -- * FIM file
    local current_file_path = request.get_current_file_path()
    if current_file_path == nil then
        -- TODO what did I do on other builders here?
        log:warn("current_file_name is nil")
        current_file_path = ""
    end
    --
    -- TODO ESCAPE sentinal tokens?
    --
    -- FYI carefully observe the format:
    --     <filename>example.py
    --     <fim_suffix>
    --
    --     # Test the function
    --     result = calculate_sum(5, 10)
    --     print(result)<fim_prefix>def calculate_sum(a, b):
    --     <fim_middle>"""
    local fim_file_contents = tokens.file_sep
        .. current_file_path
        .. "\n"
        .. tokens.fim_suffix
        .. request.suffix
        .. tokens.fim_prefix
        .. request.prefix
        .. tokens.fim_middle

    prompt = prompt .. fim_file_contents

    -- WARNING: anything after <|fim_middle|> is seen as part of the completion!


    -- alt format example
    -- f"<fim_suffix>{suffix}<fim_prefix>{prefix}<fim_middle>"


    return prompt
end

function M.starcoder2.get_spm_fim_prompt(request)
    -- TODO look into setting STOP token... I am noticing it often goes on for a very long time, endlessly
    -- esp in these comments and in test case code

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

    -- * repo_name
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


    -- WARNING: anything after <|fim_middle|> is seen as part of the completion!

    return prompt .. tokens.file_sep .. fim_file_contents
end

M.codestral = {
    -- https://docs.mistral.ai/capabilities/code_generation/
    -- by the way this repo might have reference templates for several models
    --   https://github.com/continuedev/continue/blob/main/core/llm/templates/edit/codestral.ts#L1
    --
    --
    -- TODO try codestra-2501 via API - s/b a material update to codestral 2405 (IIRC, 2024)
    --   watch for a release of it
    -- TODO try mamba-codestral via API (or its on hf and should work w/ mlx but can't figure it out yet)
    -- TODO devstral, can it do FIM?


    sentinel_tokens = {
        -- TODO is there a paper?
        -- only references I can find so far:
        --   * https://huggingface.co/mistralai/Codestral-22B-v0.1/blob/main/tokenizer_config.json
        --   https://huggingface.co/mistralai/Codestral-22B-v0.1/blob/main/special_tokens_map.json
        --   [PREFIX]
        fim_prefix = "[PREFIX]",
        fim_middle = "[MIDDLE]",
        fim_suffix = "[SUFFIX]",

        bos_token = "<s>",
        eos_token = "</s>",
        unk_token = "<unk>",

    },

}

function M.codestral.get_fim_prompt(request)
    local tokens = M.codestral.sentinel_tokens

    -- TODO! VERIFY THE FORMAT!!!! this is just a GH issue that suggested it
    -- found suggestion:
    --   https://github.com/ollama/ollama/issues/5403
    --   <s>[SUFFIX] {{ suffix }} [PREFIX] {{ prefix }}
    --    TODO this doesn't include [MIDDLE]... should I add it?
    -- TODO! try PSM format next... sometimes in calc.lua I am getting [SUFFIX] on end of response!
    local fim_file_contents = tokens.fim_suffix
        .. request.suffix
        .. tokens.fim_prefix
        .. request.prefix
        .. tokens.fim_middle -- TODO! find out about MIDDLE? completions work well enough w/ and w/o this

    -- TODO filename, multi-file, etc?
    return fim_file_contents
end

M.deepseek_coder_v2 = {
    -- https://github.com/deepseek-ai/DeepSeek-Coder-V2
    -- https://github.com/deepseek-ai/DeepSeek-Coder-V2?tab=readme-ov-file#code-insertion
    --  "lite" == 16B size
    --    * AFAICT only lite has FIM
    --  base = FIM  /  instruct = chat
    -- ** FAST MoE
    -- 217 TPS! first load OMFG
    -- model = "deepseek-coder-v2:16b-lite-base-q8_0", # **** 217 TPS!
    -- model = "deepseek-coder-v2:16b-lite-base-fp16" # TODO TRY THIS ONE
    -- TODO can I get fp in memory?!

    sentinel_tokens = {
        --
        -- FYI it's not spaces around the pipe char:
        fim_begin = "<｜fim▁begin｜>",
        fim_hole = "<｜fim▁hole｜>",
        fim_end = "<｜fim▁end｜>",

        -- TODO what name for this?
        stop_tokens = { "<|eos_token|>" }
    }

}

-- input_text = """<｜fim▁begin｜>def quick_sort(arr):
--     if len(arr) <= 1:
--         return arr
--     pivot = arr[0]
--     left = []
--     right = []
-- <｜fim▁hole｜>
--         if arr[i] < pivot:
--             left.append(arr[i])
--         else:
--             right.append(arr[i])
--     return quick_sort(left) + [pivot] + quick_sort(right)<｜fim▁end｜>"""

function M.deepseek_coder_v2.get_fim_prompt(request)
    local tokens = M.deepseek_coder_v2.sentinel_tokens

    -- PSM format:
    -- <｜fim_begin｜> 𝑓𝑝𝑟𝑒<｜fim_hole｜> 𝑓𝑠𝑢 𝑓<｜fim_end｜> 𝑓𝑚𝑖𝑑𝑑𝑙𝑒<|eos_token|>
    local fim_file_contents = tokens.fim_begin
        .. request.prefix
        .. tokens.fim_hole
        .. request.suffix
        .. tokens.fim_end

    return fim_file_contents

    -- ** paper also says at "document level" ...
    -- * can I include fileanme? (if so => yanks/edits/etc)
    -- * multiple files?
    -- return prompt .. tokens.file_sep .. fim_file_contents
end

return M
