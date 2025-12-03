local log = require("ask-openai.logs.logger").predictions()
local files = require("ask-openai.helpers.files")
local ansi = require("ask-openai.predictions.ansi")
local ChatThread = require("ask-openai.questions.chat.thread")
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")
local HarmonyRawFimPromptBuilder = require("ask-openai.backends.models.fim_harmony")

local M = {}

-- these models work for other purposes too...
--   but lets collect them under fim for now
--   really these are the fim related special tokens

M.gptoss = {
    sentinel_tokens = {}
}
---@param request FimBackend
function M.gptoss.RETIRED_get_fim_raw_prompt_no_thinking(request)
    -- FYI this builder might be useful if I want to work with raw prompts for another use case...
    --  but I found prefill in llama-cpp (llama-server) so I don't need raw anymore for FIM w/o thinking purposes

    -- TODO experiment 2 - combination of fixed thinking start + partial thinking finish
    --   add my thinking reflections from above...
    --   then let the model finish thinking?
    --   use new harmony parser for raw /completions output parsing

    -- TODO if I allow the model to finish the reasoning... that might be best!
    --   Ask it to practice its change before it decides
    -- I could update my example too:
    -- <analysis>
    -- Let's practice the change first.
    -- I need to insert a variable name between 'return' and '+ b'.
    -- Candidate: a
    -- Check: would that make 'return a + b'? Yes.
    -- So the correct insertion is 'a'.
    -- </analysis>
    -- <final>

    local builder = HarmonyRawFimPromptBuilder.new()
        :developer()
        :user(HarmonyRawFimPromptBuilder.context_user_msg(request))
        :user(HarmonyRawFimPromptBuilder.fim_prompt(request))
        :set_thinking()
        :start_assistant_final_response() -- this forces the model to respond w/o any further thinking

    return builder:build_raw_prompt()
end

---@param request FimBackend
---@param level FimReasoningLevel
function M.gptoss.get_fim_chat_messages(request, level)
    -- TODO what if I change this to ask gptoss to rewrite the current line (only current line)
    --  and then FIM just replaces that line?
    --  OR, add a shortcut key to accept FIM as replace current line?
    --  not always, but sometimes gptoss still suggests entire line (espeically for partial lines)
    --    why not work around that or encourage that?
    --    I can even diff the current line vs the generated to see what to insert so I don't have to do extmarks that replace the full line

    local dev = HarmonyRawFimPromptBuilder.developer_message
    -- FYI if/when you test out using partial thinking with raw template above, then put this into the shared developer message
    dev = dev .. [[
Make sure to practice the code change before you return a suggestion. Take the cursor line (at least) and type it out with the new code and make sure it is valid, correct code.
]]

    local messages = {
        TxChatMessage:developer(dev), -- FYI developer or system message must be first, and ONLY ONE is allowed
        TxChatMessage:user(HarmonyRawFimPromptBuilder.context_user_msg(request)),
        TxChatMessage:user(HarmonyRawFimPromptBuilder.fim_prompt(request)),
    }

    if level == "off" then
        -- TODO get rid of raw prompt approach above? or just keep it around as "RETIRED" ??
        local fixed_thoughts = HarmonyRawFimPromptBuilder.deep_thoughts_about_fim

        -- FYI "<|start|>assistant" is at end of prompt (see add_generation_prompt in jinja template + in chat logic)
        --   https://github.com/ggml-org/llama.cpp/blob/7d77f0732/models/templates/openai-gpt-oss-120b.jinja#L328-L330
        --   thus my `prefill` (below) starts with a channel
        --   BTW my `prefill` is appended to the raw prompt (after jinja is rendered):
        --     https://github.com/ggml-org/llama.cpp/blob/7d77f0732/tools/server/utils.hpp#L754-L762
        local prefill = "<|channel|>analysis<|message|>" .. fixed_thoughts .. "<|end|>"
            .. "<|start|>assistant" -- WORKS!

        -- *** notes w.r.t. final prefill text (last message)
        -- .. "<|start|>assistant" -- * WORKS!
        --   luckily, finishing prefill with `<|start|>assistant` is enough for gptoss to produce the final message!
        --   IIAC you can't have back to back analysis channel messages, or at least not normally?
        --     and commentary channel doesn't make sense because no tools passed
        --     so the model is only left with the final channel! (phew)
        --   (btw... this is the same as it would add w/o my prefill)

        -- * FAILED:
        -- .. "<|start|>assistant<|channel|>final<|message|>" -- FAIL
        -- along the way shows:
        --   llama-server: Partial parse: incomplete header
        -- at end it does recognize generated text as the content (net effect is as if it were not a streaming response b/c it all arrives on last delta!)
        --   llama-server: Partial parse: incomplete header
        --   llama-server: Parsed message: {"role":"assistant","content":"function M.mul(a, b)\n    return a * b\nend\n\nfunction M.div(a, b)\n    if b == 0 then\n        error(\"division by zero\")\n    end\n    return a / b\nend"}
        --
        -- .. "<|start|>assistant<|channel|>final"  -- FAIL
        --
        -- .. "<|start|>assistant<|channel|>" -- FAIL results in these key messages:
        --   llama-server: common_chat_parse_gpt_oss: unknown header from message: final
        --   llama-server: common_chat_parse_gpt_oss: content after last message: final<|message|>function M.mul(a, b)
        --



        -- llama-cpp uses this last assistant message for prefill purposes (will not terminate with <|end|>)
        table.insert(messages, TxChatMessage:assistant(prefill))

        -- TODO add nvim command to verify prompts:
        --   TODO AskDumpApplyTemplates (dump all in one go is probably best to compare)
    end

    return messages
end

local function qwen_tag(type)
    return "<|" .. type .. "|>"
end
M.qwen25coder = {
    sentinel_tokens = {
        -- https://huggingface.co/Qwen/Qwen2.5-Coder-14B-Instruct/blob/main/tokenizer_config.json
        fim_prefix = qwen_tag("fim_prefix"), -- 151659
        fim_middle = qwen_tag("fim_middle"), -- 151660
        fim_suffix = qwen_tag("fim_suffix"), -- 151661
        -- fim_pad = qwen_tag("fim_pad"), -- 151662
        repo_name = qwen_tag("repo_name"), -- 151663
        file_sep = qwen_tag("file_sep"), -- 151664

        im_start = qwen_tag("im_start"), -- 151644
        im_end = qwen_tag("im_end"), -- 151645
        endoftext = qwen_tag("endoftext"), -- 151643
    },
}

---@param request FimBackend
function M.qwen25coder.get_fim_prompt(request)
    -- FYI! see fim.md for extensive FIM notes
    local tokens = M.qwen25coder.sentinel_tokens

    -- TODO confirm qwen2.5coder has trailing \n after repo_name
    --   I see this in the example files: https://github.com/QwenLM/Qwen2.5-Coder/blob/f20915b77910de5ba8463547e7654beb056ec7d0/examples/Qwen2.5-Coder-repolevel-fim.py
    --   it might not matter?
    local repo_name = request:get_repo_name()
    local prompt = tokens.repo_name .. repo_name .. "\n"

    -- * FIM file
    local current_file_relative_path = request.inject_file_path_test_seam()
    if current_file_relative_path == nil then
        -- i.e. if :new and before first :w (save)
        -- for now just leave filename blank?
        --  or, maybe mark it as new?
        --   can I deterine filetype using some heuristic or other metadata?
        --   should I mark it "new"
        -- log:warn("current_file_name is nil")
        current_file_relative_path = ""
    end

    ---@param context_item ContextItem
    local function append_file_non_fim(context_item)
        -- <file_sep>filepath0\ncode0
        local non_fim_file = tokens.file_sep .. context_item.filename .. "\n"
            .. context_item.content
        prompt = prompt .. non_fim_file
    end

    local instructions = ContextItem:new("instructions", [[
General project code rules:
- Never add comments to the end of a line.
- NEVER add TODO comments for me.
]])
    append_file_non_fim(instructions)

    if request.context.includes.yanks and request.context.yanks then
        append_file_non_fim(request.context.yanks)
    end

    if request.context.includes.matching_ctags and request.context.matching_ctags then
        append_file_non_fim(request.context.matching_ctags)
    end

    if request.context.includes.project and request.context.project then
        vim.iter(request.context.project)
            :each(append_file_non_fim)
    end

    if request.rag_matches then
        -- TODO! dedupe matches that overlap/touch dedupe.merge_contiguous_rag_chunks()
        vim.iter(request.rag_matches)
            :each(function(chunk)
                ---@cast chunk LSPRankedMatch
                local file_name = chunk.file .. ":" .. chunk.start_line_base0 .. "-" .. chunk.end_line_base0
                local non_fim_file = tokens.file_sep .. file_name .. "\n" .. chunk.text
                prompt = prompt .. non_fim_file
            end)
    end

    -- * recent edits
    -- local recent_changes = "Here are some recent lines that were edited by the user: "
    -- for _, change in pairs(context.edits) do
    --     local str = string.format("Line %d, Column %d: %s", change.lnum, change.col, change.line)
    --     -- todo include line/col or not?
    --     -- todo include file?
    --     recent_changes = recent_changes .. "\n" .. str
    -- end
    -- raw_prompt = recent_changes .. "\n\n" .. raw_prompt

    -- FYI carefully observe the format:
    local fim_file_contents = tokens.file_sep
        .. current_file_relative_path
        .. "\n"
        .. tokens.fim_prefix
        .. request.ps_chunk.prefix
        .. tokens.fim_suffix
        .. request.ps_chunk.suffix
        .. tokens.fim_middle

    return prompt .. fim_file_contents
end

M.bytedance_seed_coder = {
    qwen_sentinels = {
        fim_stop_tokens_from_qwen25_coder = {
            -- observed these generaeted by Seed-Coder:
            M.qwen25coder.sentinel_tokens.endoftext, -- stops on this
            M.qwen25coder.sentinel_tokens.file_sep, -- rambles past this, so a good stop point... rambles b/c of repeating file pattern
            qwen_tag("end"), -- bytedance_seed_coder stops on this at times too, not sure this is a qwen25coder token...

            -- haven't seen Seed-Coder generate these but they don't hurt to add:
            M.qwen25coder.sentinel_tokens.im_end,
            M.qwen25coder.sentinel_tokens.fim_prefix,
            M.qwen25coder.sentinel_tokens.fim_suffix,
            M.qwen25coder.sentinel_tokens.repo_name,
        },
    },
    sentinel_tokens = {
        fim_suffix = "<[fim-suffix]>", --
        fim_prefix = "<[fim-prefix]>", --
        fim_middle = "<[fim-middle]>", --
        -- https://huggingface.co/ByteDance-Seed/Seed-Coder-8B-Base/blob/main/tokenizer_config.json

        -- THEIR TECHINCAL PAPER SAYS THEY USED REPO LEVEL training data....
        --   WHAT WAS THE FORMAT!!!! did it have tokens too.. it had to have a filename at least?
        --   https://arxiv.org/abs/2506.03524
        --     "repository-level variant preserved the project structure, enabling more coherent long-context learning"
        --     "Each repository was mapped to a single string sequence"
        --     "with exceptionally large repositories (e.g., PyTorch) being decomposed into multiple independent subgraphs"
        --     RepoCoder:
        --     - Seed-Coder paper refers to a microsoft research project called RepoCoder, which basically has RAG to find relevant code (repo level) and then prepends it commented out
        --     - https://github.com/microsoft/CodeT/tree/main/RepoCoder
        --     - PromptBuilder is key part, shows format used for retrieved code samples:
        --        https://github.com/microsoft/CodeT/blob/35f54d60b152cc31d134b788e702878ad613d9f7/RepoCoder/build_prompt.py#L24-L84
        --     - by the way RepoCoder primarily tested a two stage retrieve + gen process... whereby the model gets a second pass to generate the code after seeing the first pass
        --     - just a hypothesis that Seed-Coder's repo level training data used the same/similar format... or something else amenable b/c they refer to the eval in the SeedCoder paper and link to RepoCoder for that
    },
}

---@param request FimBackend
function M.bytedance_seed_coder.get_fim_prompt_file_level_only(request)
    -- FYI file level works well for Seed-Coder

    local tokens = M.bytedance_seed_coder.sentinel_tokens
    -- * SPM
    local file_level_prompt_only = ''
        -- PRN show FIM file path commented out?
        -- tokens.file_sep
        -- .. current_file_relative_path
        -- .. "\n"
        --
        .. tokens.fim_suffix
        .. request.ps_chunk.suffix
        .. tokens.fim_prefix
        .. request.ps_chunk.prefix
        .. tokens.fim_middle

    return file_level_prompt_only
end

---@param request FimBackend
function M.bytedance_seed_coder.get_fim_prompt_repo_level(request)
    -- FYI this is NOT working well! not yet anyways!
    --    gotta find the format they trained with, for multiple files (repo level training data)

    -- FYI! see bytedance_seed_coder_notes.md
    local tokens = M.bytedance_seed_coder.sentinel_tokens
    -- TLDR => issues with stop_token... rambles endlessly so this format must not be that close too what was trained
    --   whereas some initial testing with file_sep showed it was stopping (only issue was stop token / text changed a few times but it stopped)
    --   NEXT UP... go back to qwen25coder format and try that

    local comment = ''
    if vim.bo.filetype == "python" then
        comment = '# '
    elseif vim.bo.filetype == "lua" then
        comment = '-- '
    else
        error(" only lua and python supported for RepoCoder FIM at this time")
    end

    local seperator = comment .. ('_'):rep(50) .. '\n'
    -- it would 100% make sense to have a separator token instead of 50 dashes!

    local any_repo_files = false
    local repo_files = {
        -- FYI use explicit \n so there's no mistake on concat
        comment .. "Here are some relevant code fragments from other files of the repo:\n",
        seperator,
    }

    ---@param context_item ContextItem
    local function append_file_non_fim_RepoCoder(context_item)
        any_repo_files = true
        local lines = vim.split(context_item.content, '\n')
        -- FYI would need to adjust comment format to be language specific!
        local commented_out_content = vim.iter(lines)
            :map(function(line)
                return comment .. line
            end)
            :join("\n")

        vim.list_extend(repo_files, {
            comment .. 'the below code fragment can be found in:\n',
            comment .. context_item.filename .. "\n",
            seperator,
            commented_out_content,
            seperator,

            -- TODO change to # too?
        })
    end

    if request.context.includes.yanks and request.context.yanks then
        append_file_non_fim_RepoCoder(request.context.yanks)
    end

    if request.context.includes.matching_ctags and request.context.matching_ctags then
        append_file_non_fim_RepoCoder(request.context.matching_ctags)
    end

    if request.rag_matches then
        -- TODO! dedupe matches that overlap/touch dedupe.merge_contiguous_rag_chunks()
        vim.iter(request.rag_matches)
            :each(function(chunk)
                ---@cast chunk LSPRankedMatch
                local file_name_with_line_range = chunk.file .. ":" .. chunk.start_line_base0 .. "-" .. chunk.end_line_base0
                append_file_non_fim_RepoCoder({
                    filename = file_name_with_line_range,
                    content = chunk.text
                })
            end)
    end

    -- * FIM file
    local current_file_relative_path = request.inject_file_path_test_seam()
    if current_file_relative_path == nil then
        -- log:warn("current_file_name is nil")
        current_file_relative_path = ""
    end

    -- * SPM
    local fim_file_contents = ''
        -- PRN show FIM file path commented out?
        -- tokens.file_sep
        -- .. current_file_relative_path
        -- .. "\n"
        --
        -- fyi, no newlines
        .. tokens.fim_suffix
        .. request.ps_chunk.suffix
        .. tokens.fim_prefix
        .. request.ps_chunk.prefix
        .. tokens.fim_middle

    local prompt_lines = {}
    if any_repo_files then
        vim.list_extend(prompt_lines, repo_files)
        table.insert(prompt_lines, '"""Based on above, complete the following code:"""')
    end
    table.insert(prompt_lines, fim_file_contents)
    return table.concat(prompt_lines, "\n")
end

local function mellum_tag(type)
    return "<" .. type .. ">"
end
M.mellum = {
    -- https://huggingface.co/JetBrains/Mellum-4b-base/blob/main/special_tokens_map.json
    -- much in common with starcoder2
    sentinel_tokens = {

        -- FIM
        fim_prefix = mellum_tag("fim_prefix"),
        fim_middle = mellum_tag("fim_middle"),
        fim_suffix = mellum_tag("fim_suffix"),
        fim_pad    = mellum_tag("fim_pad"),
        -- FYI file_sep => filename, repo_name => reponame... can put that back if the prompt is unique to mellum anyways
        --  but right now I suspect it will be the same as qwen25coder and starcoder2
        file_sep   = mellum_tag("filename"),
        repo_name  = mellum_tag("reponame"),


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
    },
}

local function starcoder_tag(type)
    return "<" .. type .. ">"
end
M.starcoder2 = {
    -- PRN did starcoder v1 have diff special tokens?
    sentinel_tokens = {
        -- https://huggingface.co/bigcode/starcoder2-15b/blob/main/special_tokens_map.json
        fim_prefix = starcoder_tag("fim_prefix"),
        fim_middle = starcoder_tag("fim_middle"),
        fim_suffix = starcoder_tag("fim_suffix"),
        fim_pad = starcoder_tag("fim_pad"),
        file_sep = starcoder_tag("file_sep"),
        repo_name = starcoder_tag("repo_name"),

        endoftext = starcoder_tag("endoftext"),
        issue_start = starcoder_tag("issue_start"),
        issue_comment = starcoder_tag("issue_comment"),
        issue_closed = starcoder_tag("issue_closed"),
        jupyter_start = starcoder_tag("jupyter_start"),
        jupyter_text = starcoder_tag("jupyter_text"),
        jupyter_code = starcoder_tag("jupyter_code"),
        jupyter_output = starcoder_tag("jupyter_output"),
        jupyter_script = starcoder_tag("jupyter_script"),
        empty_output = starcoder_tag("empty_output"),
        code_to_intermediate = starcoder_tag("code_to_intermediate"),
        intermediate_to_code = starcoder_tag("intermediate_to_code"),

        pr_start = starcoder_tag("pr"),
        pr_status = starcoder_tag("pr_status"),
        pr_is_merged = starcoder_tag("pr_is_merged"),
        pr_base = starcoder_tag("pr_base"),
        pr_file = starcoder_tag("pr_file"),
        pr_base_code = starcoder_tag("pr_base_code"),
        pr_diff = starcoder_tag("pr_diff"),
        pr_diff_hunk = starcoder_tag("pr_diff_hunk"),
        pr_comment = starcoder_tag("pr_comment"),

        pr_event_id = starcoder_tag("pr_event_id"),
        pr_review = starcoder_tag("pr_review"),
        pr_review_state = starcoder_tag("pr_review_state"),
        pr_review_comment = starcoder_tag("pr_review_comment"),
        pr_in_reply_to_review_id = starcoder_tag("pr_in_reply_to_review_id"),
        pr_in_reply_to_comment_id = starcoder_tag("pr_in_reply_to_comment_id"),

        pr_diff_hunk_comment_line = starcoder_tag("pr_diff_hunk_comment_line"),

        -- starcoder_tag("NAME"),
        -- starcoder_tag("EMAIL"),
        -- starcoder_tag("KEY"),
        -- starcoder_tag("PASSWORD"),
    }
}

function M.mellum.get_fim_prompt(request)
    -- FYI! see test case for mellum, I have a bunch of notes over there
    local tokens = M.mellum.sentinel_tokens

    -- * repo_name
    local repo_name = request.get_repo_name()
    local prompt = tokens.repo_name .. repo_name

    ---@param context_item ContextItem
    local function append_file_non_fim(context_item)
        -- <filename>filepathX\ncodeX
        local non_fim_file = tokens.file_sep .. context_item.filename .. "\n" .. context_item.content
        prompt = prompt .. non_fim_file
    end

    -- * recent yanks
    if request.context.includes.yanks and request.context.yanks then
        append_file_non_fim(request.context.yanks)
    end

    -- * FIM file
    local current_file_path = request.inject_file_path_test_seam()
    if current_file_path == nil then
        -- log:warn("current_file_name is nil")
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

    ---@param context_item ContextItem
    local function append_file_non_fim(context_item)
        -- <file_sep>filepath0\ncode0
        local non_fim_file = tokens.file_sep .. context_item.filename .. "\n" .. context_item.content
        prompt = prompt .. non_fim_file
    end

    -- * recent yanks
    if request.context.includes.yanks and request.context.yanks then
        append_file_non_fim(request.context.yanks)
    end

    -- * FIM file
    local current_file_path = request.inject_file_path_test_seam()
    if current_file_path == nil then
        -- log:warn("current_file_name is nil")
        current_file_path = ""
    end
    --
    -- TODO ESCAPE presence of any sentinel tokens? i.e. should be rare but if someone is working on LLM code it may not be!
    --
    -- FYI carefully observe the format:
    --   FYI I replaced <> with __ and then uppercased tag name => _FIM_PREFIX_ (replace outer _ _ with <> and lowercase name)
    --   _FILE_SEP__FIM_PREFIX_filepath1\ncode1_pre_FIM_SUFFIX_code1_suf_FIM_MIDDLE_code1_mid
    --   _FIM_PREFIX_ comes BEFORE filepath!
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

local function codestral_tag(type)
    return "[" .. type .. "]"
end
M.codestral = {
    -- https://docs.mistral.ai/capabilities/code_generation/
    -- by the way this repo might have reference templates for several models
    --   https://github.com/continuedev/continue/blob/main/core/llm/templates/edit/codestral.ts#L1

    sentinel_tokens = {
        -- TODO is there a paper?
        -- only references I can find so far:
        --   * https://huggingface.co/mistralai/Codestral-22B-v0.1/blob/main/tokenizer_config.json
        --   https://huggingface.co/mistralai/Codestral-22B-v0.1/blob/main/special_tokens_map.json
        --   [PREFIX]
        fim_prefix = codestral_tag("PREFIX"),
        fim_middle = codestral_tag("MIDDLE"),
        fim_suffix = codestral_tag("SUFFIX"),

        eos_token = "</s>",
    },

}

function M.codestral.get_fim_prompt(request)
    local tokens = M.codestral.sentinel_tokens

    -- found suggestion:
    --   https://github.com/ollama/ollama/issues/5403
    --   FYI dropped off [] surrounding tags:
    --   <s>SUFFIX {{ suffix }} PREFIX {{ prefix }}
    --    TODO this doesn't include MIDDLE... should I add it?
    local fim_file_contents = tokens.fim_suffix
        .. request.suffix
        .. tokens.fim_prefix
        .. request.prefix
        .. tokens.fim_middle -- TODO! find out about MIDDLE? completions work well enough w/ and w/o this

    -- TODO filename, multi-file, etc?
    return fim_file_contents
end

local function deepseek_tag(type)
    -- FYI it's not spaces around the pipe char:
    return "<｜" .. type .. "｜>"
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

    sentinel_tokens = {
        fim_begin = deepseek_tag("fim▁begin"),
        fim_hole = deepseek_tag("fim▁hole"),
        fim_end = deepseek_tag("fim▁end"),

        fim_stop_tokens = { qwen_tag("eos_token") }
    }

}

function M.deepseek_coder_v2.get_fim_prompt(request)
    local tokens = M.deepseek_coder_v2.sentinel_tokens

    -- PSM format:
    local fim_file_contents = tokens.fim_begin
        .. request.prefix
        .. tokens.fim_hole
        .. request.suffix
        .. tokens.fim_end

    return fim_file_contents

    -- ** paper also says at "document level" ...
    -- * can I include filename? (if so => yanks/edits/etc)
    -- * multiple files?
    -- return prompt .. tokens.file_sep .. fim_file_contents
end

return M
